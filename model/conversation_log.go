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

func ListConversationLogs(userId int, modelName string, keyword string, start, num int) ([]*ConversationLog, int64, error) {
	tx := LOG_DB.Model(&ConversationLog{})
	if userId > 0 {
		tx = tx.Where("user_id = ?", userId)
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

// DeleteConversationLogsBefore removes rows older than the timestamp.
func DeleteConversationLogsBefore(ts int64) (int64, error) {
	res := LOG_DB.Where("created_at < ?", ts).Delete(&ConversationLog{})
	return res.RowsAffected, res.Error
}
