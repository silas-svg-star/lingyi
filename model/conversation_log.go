package model

import (
	"github.com/QuantumNous/new-api/common"
)

// ConversationLog stores the prompt/response of relay requests. It is opt-in
// (ConversationLogEnabled), disclosed to users on the signup page, readable by
// admins only, and purged automatically after ConversationLogRetentionDays.
type ConversationLog struct {
	Id         int    `json:"id" gorm:"primaryKey;autoIncrement"`
	CreatedAt  int64  `json:"created_at" gorm:"bigint;index"`
	UserId     int    `json:"user_id" gorm:"index"`
	Username   string `json:"username" gorm:"type:varchar(64);index;default:''"`
	TokenName  string `json:"token_name" gorm:"type:varchar(128);default:''"`
	ModelName  string `json:"model_name" gorm:"type:varchar(128);index;default:''"`
	Path       string `json:"path" gorm:"type:varchar(128);default:''"`
	StatusCode int    `json:"status_code"`
	IsStream   bool   `json:"is_stream"`
	Request    string `json:"request" gorm:"type:text"`
	Response   string `json:"response" gorm:"type:text"`
}

func (ConversationLog) TableName() string { return "conversation_logs" }

func CreateConversationLog(l *ConversationLog) error {
	if l.CreatedAt == 0 {
		l.CreatedAt = common.GetTimestamp()
	}
	return LOG_DB.Create(l).Error
}

func ListConversationLogs(userId int, username string, modelName string, keyword string, start, num int) ([]*ConversationLog, int64, error) {
	tx := LOG_DB.Model(&ConversationLog{})
	if userId > 0 {
		tx = tx.Where("user_id = ?", userId)
	}
	if username != "" {
		tx = tx.Where("LOWER(username) LIKE LOWER(?)", "%"+username+"%")
	}
	if modelName != "" {
		tx = tx.Where("model_name = ?", modelName)
	}
	if keyword != "" {
		like := "%" + keyword + "%"
		tx = tx.Where("request LIKE ? OR response LIKE ?", like, like)
	}
	var total int64
	if err := tx.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	var items []*ConversationLog
	err := tx.Order("id desc").Limit(num).Offset(start).Find(&items).Error
	return items, total, err
}

// ConversationLogUser is one account's entry in the per-account summary.
type ConversationLogUser struct {
	UserId   int    `json:"user_id"`
	Username string `json:"username"`
	Count    int64  `json:"count"`
	LastAt   int64  `json:"last_at"`
}

// ListConversationLogUsers groups saved conversations by account, most recent
// first, optionally narrowed by a username search.
func ListConversationLogUsers(username string) ([]ConversationLogUser, error) {
	tx := LOG_DB.Model(&ConversationLog{}).
		Select("user_id, MAX(username) AS username, COUNT(*) AS count, MAX(created_at) AS last_at").
		Group("user_id")
	if username != "" {
		tx = tx.Where("LOWER(username) LIKE LOWER(?)", "%"+username+"%")
	}
	var users []ConversationLogUser
	err := tx.Order("last_at desc").Limit(500).Scan(&users).Error
	return users, err
}

// DeleteConversationLogsBefore removes rows older than the timestamp.
func DeleteConversationLogsBefore(ts int64) (int64, error) {
	res := LOG_DB.Where("created_at < ?", ts).Delete(&ConversationLog{})
	return res.RowsAffected, res.Error
}
