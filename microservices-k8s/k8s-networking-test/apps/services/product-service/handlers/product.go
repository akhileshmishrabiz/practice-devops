package handlers

import (
	"net/http"
	"product-service/middleware"
	"product-service/models"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"gorm.io/gorm"
)

type ProductHandler struct {
	DB *gorm.DB
}

func NewProductHandler(db *gorm.DB) *ProductHandler {
	return &ProductHandler{DB: db}
}

// GetAllProducts retrieves all products with optional filtering
func (h *ProductHandler) GetAllProducts(c *gin.Context) {
	start := time.Now()
	var products []models.Product

	// Record query metric
	middleware.ProductQueriesTotal.WithLabelValues("list").Inc()

	query := h.DB.Model(&models.Product{})

	// Filter by category
	if category := c.Query("category"); category != "" {
		query = query.Where("category = ?", category)
	}

	// Filter by active status
	if isActive := c.Query("is_active"); isActive != "" {
		query = query.Where("is_active = ?", isActive == "true")
	}

	// Price range filtering
	if minPrice := c.Query("min_price"); minPrice != "" {
		if price, err := strconv.ParseFloat(minPrice, 64); err == nil {
			query = query.Where("price >= ?", price)
		}
	}
	if maxPrice := c.Query("max_price"); maxPrice != "" {
		if price, err := strconv.ParseFloat(maxPrice, 64); err == nil {
			query = query.Where("price <= ?", price)
		}
	}

	// Sorting
	sortBy := c.DefaultQuery("sort_by", "created_at")
	sortOrder := c.DefaultQuery("sort_order", "desc")
	query = query.Order(sortBy + " " + sortOrder)

	// Pagination
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	offset := (page - 1) * pageSize

	var total int64
	query.Count(&total)

	if err := query.Offset(offset).Limit(pageSize).Find(&products).Error; err != nil {
		log.WithError(err).Error("Failed to retrieve products")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve products"})
		return
	}

	// Record database query duration
	middleware.RecordDatabaseQuery("list_products", time.Since(start))

	c.JSON(http.StatusOK, gin.H{
		"products":  products,
		"page":      page,
		"page_size": pageSize,
		"total":     total,
	})
}

// GetProductByID retrieves a single product by ID
func (h *ProductHandler) GetProductByID(c *gin.Context) {
	id := c.Param("id")

	var product models.Product
	if err := h.DB.First(&product, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
			return
		}
		log.WithError(err).Error("Failed to retrieve product")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve product"})
		return
	}

	c.JSON(http.StatusOK, product)
}

// CreateProduct creates a new product
func (h *ProductHandler) CreateProduct(c *gin.Context) {
	var req models.ProductCreateRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	product := models.Product{
		Name:        req.Name,
		Description: req.Description,
		Price:       req.Price,
		Stock:       req.Stock,
		Category:    req.Category,
		ImageURL:    req.ImageURL,
		Images:      req.Images,
		SKU:         req.SKU,
		IsActive:    true,
	}

	if err := h.DB.Create(&product).Error; err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			c.JSON(http.StatusConflict, gin.H{"error": "Product with this SKU already exists"})
			return
		}
		log.WithError(err).Error("Failed to create product")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create product"})
		return
	}

	// Record metric
	middleware.ProductsCreatedTotal.Inc()

	log.WithField("product_id", product.ID).Info("Product created successfully")
	c.JSON(http.StatusCreated, product)
}

// UpdateProduct updates an existing product
func (h *ProductHandler) UpdateProduct(c *gin.Context) {
	id := c.Param("id")

	var product models.Product
	if err := h.DB.First(&product, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
			return
		}
		log.WithError(err).Error("Failed to retrieve product")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve product"})
		return
	}

	var req models.ProductUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Update fields if provided
	if req.Name != nil {
		product.Name = *req.Name
	}
	if req.Description != nil {
		product.Description = *req.Description
	}
	if req.Price != nil {
		product.Price = *req.Price
	}
	if req.Stock != nil {
		product.Stock = *req.Stock
	}
	if req.Category != nil {
		product.Category = *req.Category
	}
	if req.ImageURL != nil {
		product.ImageURL = *req.ImageURL
	}
	if req.Images != nil {
		product.Images = *req.Images
	}
	if req.SKU != nil {
		product.SKU = *req.SKU
	}
	if req.IsActive != nil {
		product.IsActive = *req.IsActive
	}

	if err := h.DB.Save(&product).Error; err != nil {
		log.WithError(err).Error("Failed to update product")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update product"})
		return
	}

	log.WithField("product_id", product.ID).Info("Product updated successfully")
	c.JSON(http.StatusOK, product)
}

// DeleteProduct soft deletes a product
func (h *ProductHandler) DeleteProduct(c *gin.Context) {
	id := c.Param("id")

	var product models.Product
	if err := h.DB.First(&product, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
			return
		}
		log.WithError(err).Error("Failed to retrieve product")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve product"})
		return
	}

	if err := h.DB.Delete(&product).Error; err != nil {
		log.WithError(err).Error("Failed to delete product")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete product"})
		return
	}

	log.WithField("product_id", id).Info("Product deleted successfully")
	c.JSON(http.StatusOK, gin.H{"message": "Product deleted successfully"})
}

// SearchProducts searches products by name or description
func (h *ProductHandler) SearchProducts(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Search query is required"})
		return
	}

	var products []models.Product
	searchPattern := "%" + strings.ToLower(query) + "%"

	if err := h.DB.Where("LOWER(name) LIKE ? OR LOWER(description) LIKE ?", searchPattern, searchPattern).
		Where("is_active = ?", true).
		Find(&products).Error; err != nil {
		log.WithError(err).Error("Failed to search products")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to search products"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"products": products})
}

// GetProductsByCategory retrieves products by category
func (h *ProductHandler) GetProductsByCategory(c *gin.Context) {
	category := c.Param("category")

	var products []models.Product
	if err := h.DB.Where("category = ? AND is_active = ?", category, true).Find(&products).Error; err != nil {
		log.WithError(err).Error("Failed to retrieve products by category")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve products"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"products": products})
}

// UpdateStock updates product stock
func (h *ProductHandler) UpdateStock(c *gin.Context) {
	id := c.Param("id")

	var product models.Product
	if err := h.DB.First(&product, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
			return
		}
		log.WithError(err).Error("Failed to retrieve product")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve product"})
		return
	}

	var req models.StockUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	switch req.Action {
	case "add":
		product.Stock += req.Quantity
	case "subtract":
		if product.Stock < req.Quantity {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Insufficient stock"})
			return
		}
		product.Stock -= req.Quantity
	case "set":
		product.Stock = req.Quantity
	}

	if err := h.DB.Save(&product).Error; err != nil {
		log.WithError(err).Error("Failed to update stock")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update stock"})
		return
	}

	log.WithFields(log.Fields{
		"product_id": product.ID,
		"action":     req.Action,
		"quantity":   req.Quantity,
		"new_stock":  product.Stock,
	}).Info("Stock updated successfully")

	c.JSON(http.StatusOK, product)
}

// CheckStock checks if a product has sufficient stock
func (h *ProductHandler) CheckStock(c *gin.Context) {
	id := c.Param("id")
	quantityStr := c.Query("quantity")

	quantity, err := strconv.Atoi(quantityStr)
	if err != nil || quantity <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid quantity"})
		return
	}

	var product models.Product
	if err := h.DB.First(&product, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
			return
		}
		log.WithError(err).Error("Failed to retrieve product")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve product"})
		return
	}

	available := product.Stock >= quantity

	c.JSON(http.StatusOK, gin.H{
		"product_id": product.ID,
		"available":  available,
		"stock":      product.Stock,
		"requested":  quantity,
	})
}

// GetCategories retrieves all unique categories
func (h *ProductHandler) GetCategories(c *gin.Context) {
	var categories []string

	if err := h.DB.Model(&models.Product{}).
		Distinct("category").
		Where("is_active = ?", true).
		Pluck("category", &categories).Error; err != nil {
		log.WithError(err).Error("Failed to retrieve categories")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve categories"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"categories": categories})
}

// HealthCheck endpoint
func (h *ProductHandler) HealthCheck(c *gin.Context) {
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
		"service":  "product-service",
		"database": "connected",
	})
}
