package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"product-service/models"
	"testing"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupTestDB() *gorm.DB {
	db, _ := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	db.AutoMigrate(&models.Product{})
	return db
}

func setupRouter(db *gorm.DB) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	h := NewProductHandler(db)

	r.GET("/health", h.HealthCheck)
	r.GET("/api/v1/products", h.GetAllProducts)
	r.GET("/api/v1/products/:id", h.GetProductByID)
	r.POST("/api/v1/products", h.CreateProduct)
	r.PUT("/api/v1/products/:id", h.UpdateProduct)
	r.DELETE("/api/v1/products/:id", h.DeleteProduct)
	r.GET("/api/v1/products/search", h.SearchProducts)
	r.PUT("/api/v1/products/:id/stock", h.UpdateStock)

	return r
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

func TestCreateProduct(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	product := models.ProductCreateRequest{
		Name:        "Test Product",
		Description: "Test Description",
		Price:       99.99,
		Stock:       100,
		Category:    "Electronics",
		SKU:         "TEST-001",
	}

	body, _ := json.Marshal(product)
	req, _ := http.NewRequest("POST", "/api/v1/products", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("Expected status 201, got %d", w.Code)
	}

	var response models.Product
	json.Unmarshal(w.Body.Bytes(), &response)

	if response.Name != "Test Product" {
		t.Errorf("Expected name 'Test Product', got '%s'", response.Name)
	}
	if response.Price != 99.99 {
		t.Errorf("Expected price 99.99, got %f", response.Price)
	}
}

func TestCreateProductValidation(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	// Missing required fields
	product := map[string]interface{}{
		"description": "Test Description",
	}

	body, _ := json.Marshal(product)
	req, _ := http.NewRequest("POST", "/api/v1/products", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("Expected status 400, got %d", w.Code)
	}
}

func TestGetProductByID(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	// Create a product first
	product := models.Product{
		Name:     "Test Product",
		Price:    50.00,
		Stock:    10,
		Category: "Books",
		IsActive: true,
	}
	db.Create(&product)

	req, _ := http.NewRequest("GET", "/api/v1/products/1", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response models.Product
	json.Unmarshal(w.Body.Bytes(), &response)

	if response.Name != "Test Product" {
		t.Errorf("Expected name 'Test Product', got '%s'", response.Name)
	}
}

func TestGetProductNotFound(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	req, _ := http.NewRequest("GET", "/api/v1/products/999", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("Expected status 404, got %d", w.Code)
	}
}

func TestUpdateStock(t *testing.T) {
	db := setupTestDB()
	router := setupRouter(db)

	// Create a product
	product := models.Product{
		Name:     "Stock Test",
		Price:    25.00,
		Stock:    50,
		Category: "Test",
		IsActive: true,
	}
	db.Create(&product)

	// Add stock
	stockReq := models.StockUpdateRequest{
		Quantity: 10,
		Action:   "add",
	}
	body, _ := json.Marshal(stockReq)
	req, _ := http.NewRequest("PUT", "/api/v1/products/1/stock", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response models.Product
	json.Unmarshal(w.Body.Bytes(), &response)

	if response.Stock != 60 {
		t.Errorf("Expected stock 60, got %d", response.Stock)
	}
}
