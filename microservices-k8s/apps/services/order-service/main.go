package main

import (
	"fmt"
	"order-service/config"
	"order-service/database"
	"order-service/messaging"
	"order-service/routes"
	"os"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
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
	log.Info("Starting Order Service...")

	// Load configuration
	cfg := config.LoadConfig()

	// Connect to database
	db := database.Connect(cfg)

	// Auto migrate models
	database.Migrate(db)

	// Connect to RabbitMQ
	rabbitMQ := messaging.NewRabbitMQ(cfg)
	if err := rabbitMQ.Connect(); err != nil {
		log.WithError(err).Fatal("Failed to connect to RabbitMQ")
	}
	defer rabbitMQ.Close()

	// Initialize Gin router
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.Default()

	// Configure CORS
	corsConfig := cors.DefaultConfig()
	corsConfig.AllowAllOrigins = true
	corsConfig.AllowHeaders = []string{"Origin", "Content-Length", "Content-Type", "Authorization"}
	corsConfig.AllowMethods = []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"}
	router.Use(cors.New(corsConfig))

	// Setup routes
	routes.SetupRoutes(router, db, rabbitMQ)

	// Start server
	port := cfg.Port
	if port == "" {
		port = "8004"
	}

	log.WithField("port", port).Info("Order Service is running")
	if err := router.Run(fmt.Sprintf(":%s", port)); err != nil {
		log.WithError(err).Fatal("Failed to start server")
	}
}
