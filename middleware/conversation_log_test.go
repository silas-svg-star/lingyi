package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/QuantumNous/new-api/common"
	"github.com/QuantumNous/new-api/model"
	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func TestConversationLogCapturesWhenEnabled(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:convlog?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	old := model.LOG_DB
	model.LOG_DB = db
	defer func() { model.LOG_DB = old; common.ConversationLogEnabled = false }()
	if err := db.AutoMigrate(&model.ConversationLog{}); err != nil {
		t.Fatal(err)
	}
	r := gin.New()
	r.Use(BodyStorageCleanup(), ConversationLog())
	r.POST("/v1/chat/completions", func(c *gin.Context) { c.String(200, "hello answer") })
	do := func() {
		req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"messages":"hi"}`))
		r.ServeHTTP(httptest.NewRecorder(), req)
	}
	count := func() int64 { var n int64; db.Model(&model.ConversationLog{}).Count(&n); return n }

	common.ConversationLogEnabled = false
	do()
	time.Sleep(200 * time.Millisecond)
	if count() != 0 {
		t.Fatal("logged while disabled")
	}
	common.ConversationLogEnabled = true
	do()
	time.Sleep(300 * time.Millisecond)
	var row model.ConversationLog
	if db.First(&row).Error != nil || row.Request != `{"messages":"hi"}` || row.Response != "hello answer" {
		t.Fatalf("bad row: %+v", row)
	}
	if n, _ := model.DeleteConversationLogsBefore(time.Now().Add(time.Hour).Unix()); n != 1 || count() != 0 {
		t.Fatal("cleanup failed")
	}
}
