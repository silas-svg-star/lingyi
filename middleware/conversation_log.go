package middleware

import (
	"bytes"
	"strconv"
	"strings"

	"github.com/QuantumNous/new-api/common"
	"github.com/QuantumNous/new-api/constant"
	"github.com/QuantumNous/new-api/model"
	"github.com/gin-gonic/gin"
)

const conversationLogMaxBytes = 64 * 1024

type conversationLogWriter struct {
	gin.ResponseWriter
	buf bytes.Buffer
}

func (w *conversationLogWriter) capture(b []byte) {
	if room := conversationLogMaxBytes - w.buf.Len(); room > 0 {
		if len(b) > room {
			b = b[:room]
		}
		w.buf.Write(b)
	}
}

func (w *conversationLogWriter) Write(b []byte) (int, error) {
	w.capture(b)
	return w.ResponseWriter.Write(b)
}

func (w *conversationLogWriter) WriteString(s string) (int, error) {
	w.capture([]byte(s))
	return w.ResponseWriter.WriteString(s)
}

func truncateUTF8(b []byte, max int) string {
	if len(b) > max {
		b = b[:max]
	}
	return strings.ToValidUTF8(string(b), "")
}

// ConversationLog records prompt and response when the admin has enabled
// disclosed conversation logging. It is a no-op while the switch is off.
func ConversationLog() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !common.ConversationLogEnabled || c.Request.Method != "POST" {
			c.Next()
			return
		}
		var reqBody string
		if storage, err := common.GetBodyStorage(c); err == nil && storage != nil && !storage.IsDisk() {
			if data, err := storage.Bytes(); err == nil {
				reqBody = truncateUTF8(data, conversationLogMaxBytes)
			}
		}
		w := &conversationLogWriter{ResponseWriter: c.Writer}
		c.Writer = w
		c.Next()

		entry := &model.ConversationLog{
			UserId:     common.GetContextKeyInt(c, constant.ContextKeyUserId),
			Username:   common.GetContextKeyString(c, constant.ContextKeyUserName),
			TokenName:  "#" + strconv.Itoa(common.GetContextKeyInt(c, constant.ContextKeyTokenId)),
			ModelName:  common.GetContextKeyString(c, constant.ContextKeyOriginalModel),
			Path:       c.Request.URL.Path,
			StatusCode: c.Writer.Status(),
			IsStream:   strings.Contains(c.Writer.Header().Get("Content-Type"), "event-stream"),
			Request:    reqBody,
			Response:   truncateUTF8(w.buf.Bytes(), conversationLogMaxBytes),
		}
		go func() {
			if err := model.CreateConversationLog(entry); err != nil {
				common.SysError("failed to save conversation log: " + err.Error())
			}
		}()
	}
}
