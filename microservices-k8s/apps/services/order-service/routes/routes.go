package routes

import (
	"order-service/config"
	"order-service/handlers"
	"order-service/messaging"
	"order-service/middleware"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func SetupRoutes(router *gin.Engine, db *gorm.DB, mq *messaging.RabbitMQ) {
	cfg := config.LoadConfig()
	orderHandler := handlers.NewOrderHandler(db, mq, cfg.CartServiceURL, cfg.ProductServiceURL)

	// Health check
	router.GET("/health", orderHandler.HealthCheck)

	// API v1 routes
	v1 := router.Group("/api/v1")
	v1.Use(middleware.Authenticate(cfg.JWTSecret))
	{
		orders := v1.Group("/orders")
		{
			orders.POST("", orderHandler.CreateOrder)
			orders.GET("/:id", orderHandler.GetOrder)
			orders.GET("", orderHandler.GetUserOrders)
			orders.PUT("/:id/status", orderHandler.UpdateOrderStatus)
		}
	}
}
