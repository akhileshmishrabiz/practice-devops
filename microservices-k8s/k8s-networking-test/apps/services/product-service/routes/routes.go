package routes

import (
	"product-service/handlers"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func SetupRoutes(router *gin.Engine, db *gorm.DB) {
	productHandler := handlers.NewProductHandler(db)

	// Health check
	router.GET("/health", productHandler.HealthCheck)

	// API v1 routes
	v1 := router.Group("/api/v1")
	{
		// Products
		products := v1.Group("/products")
		{
			products.GET("", productHandler.GetAllProducts)
			products.GET("/:id", productHandler.GetProductByID)
			products.POST("", productHandler.CreateProduct)
			products.PUT("/:id", productHandler.UpdateProduct)
			products.DELETE("/:id", productHandler.DeleteProduct)

			// Search and filtering
			products.GET("/search", productHandler.SearchProducts)
			products.GET("/category/:category", productHandler.GetProductsByCategory)
			products.GET("/categories", productHandler.GetCategories)

			// Stock management
			products.PUT("/:id/stock", productHandler.UpdateStock)
			products.GET("/:id/stock/check", productHandler.CheckStock)
		}
	}
}
