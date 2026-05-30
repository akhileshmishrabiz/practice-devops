package main

import (
	"fmt"
	"os"
	"product-service/config"
	"product-service/database"
	"product-service/middleware"
	"product-service/routes"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	log "github.com/sirupsen/logrus"
)

func init() {
	// Load .env file if it exists
	if err := godotenv.Load(); err != nil {
		log.Warn("No .env file found")
	}

	// Configure logging
	log.SetFormatter(&log.JSONFormatter{})
	log.SetOutput(os.Stdout)
	logLevel := os.Getenv("LOG_LEVEL")
	if logLevel == "" {
		logLevel = "info"
	}
	level, err := log.ParseLevel(logLevel)
	if err != nil {
		level = log.InfoLevel
	}
	log.SetLevel(level)
}

func main() {
	log.Info("Starting Product Service...")

	// Load configuration
	cfg := config.LoadConfig()

	// Connect to database
	db := database.Connect(cfg)

	// Auto migrate models
	database.Migrate(db)

	// Initialize Gin router
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()

	// Add middleware in order
	router.Use(gin.Recovery()) // Panic recovery
	router.Use(middleware.LoggingMiddleware()) // Structured logging
	router.Use(middleware.PrometheusMiddleware()) // Prometheus metrics

	// Configure CORS
	corsConfig := cors.DefaultConfig()
	corsConfig.AllowAllOrigins = true
	corsConfig.AllowHeaders = []string{"Origin", "Content-Length", "Content-Type", "Authorization"}
	corsConfig.AllowMethods = []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"}
	router.Use(cors.New(corsConfig))

	// Prometheus metrics endpoint
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Setup routes
	routes.SetupRoutes(router, db)

	// Start server
	port := cfg.Port
	if port == "" {
		port = "8001"
	}

	log.WithField("port", port).Info("Product Service is running")
	if err := router.Run(fmt.Sprintf(":%s", port)); err != nil {
		log.WithError(err).Fatal("Failed to start server")
	}
}
