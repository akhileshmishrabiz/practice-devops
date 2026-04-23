package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"order-service/messaging"
	"order-service/models"

	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"gorm.io/gorm"
)

type OrderHandler struct {
	DB               *gorm.DB
	RabbitMQ         *messaging.RabbitMQ
	CartServiceURL   string
	ProductServiceURL string
}

func NewOrderHandler(db *gorm.DB, mq *messaging.RabbitMQ, cartURL, productURL string) *OrderHandler {
	return &OrderHandler{
		DB:                db,
		RabbitMQ:          mq,
		CartServiceURL:    cartURL,
		ProductServiceURL: productURL,
	}
}

type CartItem struct {
	ProductID int     `json:"productId"`
	Name      string  `json:"name"`
	Price     float64 `json:"price"`
	Quantity  int     `json:"quantity"`
}

type CartResponse struct {
	Items []CartItem `json:"items"`
	Total float64    `json:"total"`
}

func (h *OrderHandler) CreateOrder(c *gin.Context) {
	userID, _ := c.Get("userId")
	email, _ := c.Get("email")

	var req models.CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get cart items
	cartURL := fmt.Sprintf("%s/api/v1/cart", h.CartServiceURL)
	httpReq, _ := http.NewRequest("GET", cartURL, nil)
	httpReq.Header.Set("Authorization", c.GetHeader("Authorization"))

	client := &http.Client{}
	resp, err := client.Do(httpReq)
	if err != nil {
		log.WithError(err).Error("Failed to get cart")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get cart"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to retrieve cart"})
		return
	}

	body, _ := io.ReadAll(resp.Body)
	var cart CartResponse
	if err := json.Unmarshal(body, &cart); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to parse cart"})
		return
	}

	if len(cart.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cart is empty"})
		return
	}

	// Create order
	tax := cart.Total * 0.1 // 10% tax
	totalAmount := cart.Total + tax

	order := models.Order{
		UserID:          userID.(string),
		UserEmail:       email.(string),
		Status:          models.OrderStatusPending,
		TotalAmount:     totalAmount,
		Tax:             tax,
		ShippingAddress: req.ShippingAddress,
		City:            req.City,
		State:           req.State,
		ZipCode:         req.ZipCode,
		Country:         req.Country,
	}

	// Create order items
	var orderItems []models.OrderItem
	var eventItems []map[string]interface{}

	for _, item := range cart.Items {
		subtotal := item.Price * float64(item.Quantity)
		orderItem := models.OrderItem{
			ProductID: item.ProductID,
			Name:      item.Name,
			Price:     item.Price,
			Quantity:  item.Quantity,
			Subtotal:  subtotal,
		}
		orderItems = append(orderItems, orderItem)

		eventItems = append(eventItems, map[string]interface{}{
			"product_id": item.ProductID,
			"name":       item.Name,
			"price":      item.Price,
			"quantity":   item.Quantity,
		})
	}

	order.Items = orderItems

	// Save to database
	if err := h.DB.Create(&order).Error; err != nil {
		log.WithError(err).Error("Failed to create order")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create order"})
		return
	}

	// Publish order event
	event := messaging.OrderEvent{
		EventType:   "order_created",
		OrderID:     order.ID,
		UserID:      order.UserID,
		UserEmail:   order.UserEmail,
		TotalAmount: order.TotalAmount,
		Items:       eventItems,
		Timestamp:   order.CreatedAt,
	}

	if err := h.RabbitMQ.PublishOrderEvent(event); err != nil {
		log.WithError(err).Warn("Failed to publish order event")
	}

	// Clear cart after successful order
	clearCartURL := fmt.Sprintf("%s/api/v1/cart", h.CartServiceURL)
	clearReq, _ := http.NewRequest("DELETE", clearCartURL, nil)
	clearReq.Header.Set("Authorization", c.GetHeader("Authorization"))
	if _, err := client.Do(clearReq); err != nil {
		log.WithError(err).Warn("Failed to clear cart after order")
	}

	log.WithField("order_id", order.ID).Info("Order created successfully")

	c.JSON(http.StatusCreated, order)
}

func (h *OrderHandler) GetOrder(c *gin.Context) {
	orderID := c.Param("id")
	userID, _ := c.Get("userId")

	var order models.Order
	if err := h.DB.Preload("Items").Where("id = ? AND user_id = ?", orderID, userID).First(&order).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
			return
		}
		log.WithError(err).Error("Failed to retrieve order")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve order"})
		return
	}

	c.JSON(http.StatusOK, order)
}

func (h *OrderHandler) GetUserOrders(c *gin.Context) {
	userID, _ := c.Get("userId")

	var orders []models.Order
	if err := h.DB.Preload("Items").Where("user_id = ?", userID).Order("created_at DESC").Find(&orders).Error; err != nil {
		log.WithError(err).Error("Failed to retrieve orders")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve orders"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"orders": orders})
}

func (h *OrderHandler) UpdateOrderStatus(c *gin.Context) {
	orderID := c.Param("id")

	var req models.UpdateOrderStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate status
	validStatuses := map[models.OrderStatus]bool{
		models.OrderStatusPending:        true,
		models.OrderStatusPaymentPending: true,
		models.OrderStatusConfirmed:      true,
		models.OrderStatusProcessing:     true,
		models.OrderStatusShipped:        true,
		models.OrderStatusDelivered:      true,
		models.OrderStatusCancelled:      true,
	}
	if !validStatuses[req.Status] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid status. Must be one of: pending, payment_pending, confirmed, processing, shipped, delivered, cancelled"})
		return
	}

	var order models.Order
	if err := h.DB.First(&order, "id = ?", orderID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve order"})
		return
	}

	order.Status = req.Status

	if err := h.DB.Save(&order).Error; err != nil {
		log.WithError(err).Error("Failed to update order status")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update order status"})
		return
	}

	log.WithFields(log.Fields{
		"order_id": orderID,
		"status":   req.Status,
	}).Info("Order status updated")

	c.JSON(http.StatusOK, order)
}

func (h *OrderHandler) HealthCheck(c *gin.Context) {
	sqlDB, err := h.DB.DB()
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":   "unhealthy",
			"database": "error",
		})
		return
	}

	if err := sqlDB.Ping(); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":   "unhealthy",
			"database": "disconnected",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":   "healthy",
		"service":  "order-service",
		"database": "connected",
	})
}
