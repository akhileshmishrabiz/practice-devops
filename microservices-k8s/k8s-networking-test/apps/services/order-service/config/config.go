package config

import "os"

type Config struct {
	Environment     string
	Port            string
	DBHost          string
	DBPort          string
	DBUser          string
	DBPassword      string
	DBName          string
	RabbitMQHost    string
	RabbitMQPort    string
	RabbitMQUser    string
	RabbitMQPass    string
	JWTSecret       string
	CartServiceURL  string
	ProductServiceURL string
}

func LoadConfig() *Config {
	return &Config{
		Environment:       getEnv("GO_ENV", "development"),
		Port:              getEnv("PORT", "8004"),
		DBHost:            getEnv("ORDER_DB_HOST", "localhost"),
		DBPort:            getEnv("ORDER_DB_PORT", "5432"),
		DBUser:            getEnv("ORDER_DB_USER", "ecommerce_user"),
		DBPassword:        getEnv("ORDER_DB_PASSWORD", "secure_password_123"),
		DBName:            getEnv("ORDER_DB_NAME", "orders"),
		RabbitMQHost:      getEnv("RABBITMQ_HOST", "localhost"),
		RabbitMQPort:      getEnv("RABBITMQ_PORT", "5672"),
		RabbitMQUser:      getEnv("RABBITMQ_USER", "guest"),
		RabbitMQPass:      getEnv("RABBITMQ_PASSWORD", "guest"),
		JWTSecret:         getEnv("JWT_SECRET", "your-super-secret-jwt-key-change-this-in-production"),
		CartServiceURL:    getEnv("CART_SERVICE_URL", "http://localhost:8003"),
		ProductServiceURL: getEnv("PRODUCT_SERVICE_URL", "http://localhost:8001"),
	}
}

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}
