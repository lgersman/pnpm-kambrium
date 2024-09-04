# syntax=docker/dockerfile:1.4

FROM golang:1.23-bookworm as build

ARG GLOW_VERSION

# RUN go install github.com/charmbracelet/gum@latest
RUN CGO_ENABLED=0 go install github.com/charmbracelet/glow@v${GLOW_VERSION}

# FROM gcr.io/distroless/base-debian12
FROM gcr.io/distroless/static-debian12

COPY --from=build /go/bin/glow /bin/

ENTRYPOINT ["/bin/glow"]

