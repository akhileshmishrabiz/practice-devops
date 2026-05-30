package config

import "os"

type Config struct {
	Environment string
	Port        string
	DBHost      string
	DBPort      string
	DBUser      string
	DBPassword  string
	DBName      string
}

func LoadConfig() *Config {
	return &Config{
		Environment: getEnv("GO_ENV", "development"),
		Port:        getEnv("PORT", "8001"),
		DBHost:      getEnv("PRODUCT_DB_HOST", "localhost"),
		DBPort:      getEnv("PRODUCT_DB_PORT", "5432"),
		DBUser:      getEnv("PRODUCT_DB_USER", "ecommerce_user"),
		DBPassword:  getEnv("PRODUCT_DB_PASSWORD", "secure_password_123"),
		DBName:      getEnv("PRODUCT_DB_NAME", "products"),
	}
}

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}
