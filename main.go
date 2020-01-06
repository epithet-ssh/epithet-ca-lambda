package main

import (
	"context"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
	"github.com/awslabs/aws-lambda-go-api-proxy/httpadapter"
	"github.com/epithet-ssh/epithet/pkg/ca"
	"github.com/epithet-ssh/epithet/pkg/caserver"
	"github.com/epithet-ssh/epithet/pkg/sshcert"
	"github.com/go-chi/chi"
	"github.com/go-chi/chi/middleware"
)

func main() {

	policyURL := os.Getenv("POLICY_URL")

	privkeySecretName := os.Getenv("PRIVKEY_SECRET_NAME")

	sess := session.Must(session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	}))

	svc := secretsmanager.New(sess)
	rs, err := svc.GetSecretValue(&secretsmanager.GetSecretValueInput{
		SecretId: aws.String(privkeySecretName),
	})
	if err != nil {
		panic(err)
	}

	privKey := aws.StringValue(rs.SecretString)

	c, err := ca.New(sshcert.RawPrivateKey(string(privKey)), policyURL)
	if err != nil {
		panic(err)
	}

	r := chi.NewRouter()

	// A good base middleware stack
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(60 * time.Second))

	r.Handle("/", caserver.New(c))

	adapter := httpadapter.New(r)
	h := handler{
		mux: adapter,
	}
	lambda.Start(h.Handle)
}

type handler struct {
	mux *httpadapter.HandlerAdapter
}

// Handle handles lambda invocations :-)
func (h *handler) Handle(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	return h.mux.ProxyWithContext(ctx, req)
}
