package controller

import (
	"strconv"
	"time"

	"github.com/QuantumNous/new-api/common"
	"github.com/QuantumNous/new-api/model"
	"github.com/gin-gonic/gin"
)

// GetConversationLogs lists saved conversations (admin only).
func GetConversationLogs(c *gin.Context) {
	pageInfo := common.GetPageQuery(c)
	userId, _ := strconv.Atoi(c.Query("user_id"))
	items, total, err := model.ListConversationLogs(userId, c.Query("model_name"), c.Query("keyword"), pageInfo.GetStartIdx(), pageInfo.GetPageSize())
	if err != nil {
		common.ApiError(c, err)
		return
	}
	pageInfo.SetTotal(int(total))
	pageInfo.SetItems(items)
	common.ApiSuccess(c, pageInfo)
}

// StartConversationLogCleanup purges rows older than the retention window.
func StartConversationLogCleanup() {
	for {
		days := common.ConversationLogRetentionDays
		if days < 1 {
			days = 7
		}
		cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour).Unix()
		if n, err := model.DeleteConversationLogsBefore(cutoff); err != nil {
			common.SysError("conversation log cleanup failed: " + err.Error())
		} else if n > 0 {
			common.SysLog("conversation log cleanup removed rows: " + strconv.FormatInt(n, 10))
		}
		time.Sleep(time.Hour)
	}
}
