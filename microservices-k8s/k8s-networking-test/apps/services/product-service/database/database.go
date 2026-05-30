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

	sqlDB, err := db.DB()
	if err != nil {
		log.WithError(err).Fatal("Failed to get database instance")
	}

	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	return db
}

func tableExists(db *gorm.DB, name string) bool {
	var count int64
	if err := db.Raw(
		"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = CURRENT_SCHEMA() AND table_name = ?",
		name,
	).Scan(&count).Error; err != nil {
		return false
	}
	return count > 0
}

func Migrate(db *gorm.DB) {
	log.Info("Running database migrations...")

	err := db.AutoMigrate(
		&models.Product{},
	)
	if err != nil {
		if tableExists(db, "products") {
			log.WithError(err).Warn("AutoMigrate failed but required tables exist; continuing")
			return
		}
		log.WithError(err).Fatal("Failed to run migrations")
	}

	log.Info("Database migrations completed successfully")
}
