package database

import (
	"fmt"
	"product-service/config"
	"product-service/models"
	"time"

	log "github.com/sirupsen/logrus"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func Connect(cfg *config.Config) *gorm.DB {
	dsn := fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s port=%s sslmode=disable TimeZone=UTC",
		cfg.DBHost,
		cfg.DBUser,
		cfg.DBPassword,
		cfg.DBName,
		cfg.DBPort,
	)

	var db *gorm.DB
	var err error

	// Retry connection up to 5 times
	for i := 0; i < 5; i++ {
		db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{
			Logger: logger.Default.LogMode(logger.Info),
		})

		if err == nil {
			log.Info("Successfully connected to database")
			break
		}

		log.WithError(err).Warnf("Failed to connect to database, retrying... (attempt %d/5)", i+1)
		time.Sleep(time.Second * 5)
	}

	if err != nil {
		log.WithError(err).Fatal("Failed to connect to database after 5 attempts")
	}

	// Configure connection pool
	sqlDB, err := db.DB()
	if err != nil {
		log.WithError(err).Fatal("Failed to get database instance")
	}

	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	return db
}

func Migrate(db *gorm.DB) {
	log.Info("Running database migrations...")

	err := db.AutoMigrate(
		&models.Product{},
	)

	if err != nil {
		log.WithError(err).Fatal("Failed to run migrations")
	}

	log.Info("Database migrations completed successfully")
}
