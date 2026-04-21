package messaging

import (
	"encoding/json"
	"fmt"
	"order-service/config"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
	log "github.com/sirupsen/logrus"
)

type RabbitMQ struct {
	conn    *amqp.Connection
	channel *amqp.Channel
	config  *config.Config
}

type OrderEvent struct {
	EventType   string                 `json:"event_type"`
	OrderID     string                 `json:"order_id"`
	UserID      string                 `json:"user_id"`
	UserEmail   string                 `json:"user_email"`
	TotalAmount float64                `json:"total_amount"`
	Items       []map[string]interface{} `json:"items"`
	Timestamp   time.Time              `json:"timestamp"`
}

func NewRabbitMQ(cfg *config.Config) *RabbitMQ {
	return &RabbitMQ{config: cfg}
}

func (r *RabbitMQ) Connect() error {
	url := fmt.Sprintf("amqp://%s:%s@%s:%s/",
		r.config.RabbitMQUser,
		r.config.RabbitMQPass,
		r.config.RabbitMQHost,
		r.config.RabbitMQPort,
	)

	var err error
	for i := 0; i < 5; i++ {
		r.conn, err = amqp.Dial(url)
		if err == nil {
			break
		}
		log.WithError(err).Warnf("Failed to connect to RabbitMQ, retrying... (attempt %d/5)", i+1)
		time.Sleep(time.Second * 5)
	}

	if err != nil {
		return fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	r.channel, err = r.conn.Channel()
	if err != nil {
		return fmt.Errorf("failed to open channel: %w", err)
	}

	// Declare exchange
	err = r.channel.ExchangeDeclare(
		"order_events", // name
		"topic",        // type
		true,           // durable
		false,          // auto-deleted
		false,          // internal
		false,          // no-wait
		nil,            // arguments
	)
	if err != nil {
		return fmt.Errorf("failed to declare exchange: %w", err)
	}

	log.Info("Successfully connected to RabbitMQ")
	return nil
}

func (r *RabbitMQ) PublishOrderEvent(event OrderEvent) error {
	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	err = r.channel.Publish(
		"order_events",        // exchange
		"order.created",       // routing key
		false,                 // mandatory
		false,                 // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        body,
			Timestamp:   time.Now(),
		},
	)

	if err != nil {
		return fmt.Errorf("failed to publish event: %w", err)
	}

	log.WithFields(log.Fields{
		"event_type": event.EventType,
		"order_id":   event.OrderID,
	}).Info("Order event published")

	return nil
}

func (r *RabbitMQ) Close() {
	if r.channel != nil {
		r.channel.Close()
	}
	if r.conn != nil {
		r.conn.Close()
	}
}
