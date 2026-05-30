package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"order-service/models"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupTestDB() *gorm.DB {
	db, _ := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	db.AutoMigrate(&models.Order{}, &models.OrderItem{})
	return db
}

func setupRouter(db *gorm.DB) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	h := NewOrderHandler(db, nil, "", "")

	r.GET("/health", h.HealthCheck)
	r.GET("/api/v1/orders/:id", func(c *gin.Context) {
		c.Set("userId", "test-user-123")
		h.GetOrder(c)
	})
	r.GET("/api/v1/orders", func(c *gin.Context) {
		c.Set("userId", "test-user-123")
		h.GetUserOrders(c)
	})
	r.PUT("/api/v1/orders/:id/status", h.UpdateOrderStatus)

	return r
}

func createTestOrder(db *gorm.DB) models.Order {
	order := models.Order{
		ID:              uuid.New().String(),
		UserID:          "test-user-123",
		UserEmail:       "test@example.com",
		Status:          models.OrderStatusPending,
		TotalAmount:     199.99,
		Tax:             19.99,
		ShippingAddress: "123 Test St",
		City:            "Test City",
		State:           "TS",
		ZipCode:         "12345",
		Country:         "India",
	}
	db.Create(&order)
	return order
}

func TestHealthCheck(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	req, _ := http.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &response)

	if response["status"] != "healthy" {
		t.Errorf("Expected status 'healthy', got '%v'", response["status"])
	}
}

func TestGetOrderByID(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	// Create a test order
	order := createTestOrder(db)

	req, _ := http.NewRequest("GET", "/api/v1/orders/"+order.ID, nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response models.Order
	json.Unmarshal(w.Body.Bytes(), &response)

	if response.UserEmail != "test@example.com" {
		t.Errorf("Expected email 'test@example.com', got '%s'", response.UserEmail)
	}
}

func TestGetOrderNotFound(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	fakeID := uuid.New().String()
	req, _ := http.NewRequest("GET", "/api/v1/orders/"+fakeID, nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("Expected status 404, got %d", w.Code)
	}
}

func TestUpdateOrderStatus(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	order := createTestOrder(db)

	statusUpdate := models.UpdateOrderStatusRequest{Status: models.OrderStatusConfirmed}
	body, _ := json.Marshal(statusUpdate)

	req, _ := http.NewRequest("PUT", "/api/v1/orders/"+order.ID+"/status", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	// Verify the status was updated
	var updatedOrder models.Order
	db.First(&updatedOrder, "id = ?", order.ID)

	if updatedOrder.Status != models.OrderStatusConfirmed {
		t.Errorf("Expected status 'confirmed', got '%s'", updatedOrder.Status)
	}
}

func TestUpdateOrderStatusInvalid(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	order := createTestOrder(db)

	statusUpdate := map[string]string{"status": "invalid_status"}
	body, _ := json.Marshal(statusUpdate)

	req, _ := http.NewRequest("PUT", "/api/v1/orders/"+order.ID+"/status", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("Expected status 400, got %d", w.Code)
	}
}

func TestOrderModel(t *testing.T) {
	order := models.Order{
		ID:          uuid.New().String(),
		UserID:      "user-123",
		TotalAmount: 100.00,
		Tax:         10.00,
		Status:      models.OrderStatusPending,
	}

	if order.Status != models.OrderStatusPending {
		t.Errorf("Expected status 'pending', got '%s'", order.Status)
	}

	if order.TotalAmount != 100.00 {
		t.Errorf("Expected total 100.00, got %f", order.TotalAmount)
	}
}
