# Compila o site Flutter (modo servidor: API em /api, mesmo domínio) e o copia para o volume
# compartilhado com o Caddy. Contexto de build: a RAIZ do repositório (veja docker-compose.yml).
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
COPY lib ./lib
# A pasta "web" não é versionada: gera o esqueleto em local temporário e copia.
RUN flutter create --platforms=web --project-name mente_saudavel /tmp/gerado \
 && cp -r /tmp/gerado/web ./web \
 && flutter pub get \
 && flutter build web --release --dart-define=API_URL=/api --no-web-resources-cdn

FROM alpine:3.20
COPY --from=build /app/build/web /web
# Ao subir, publica o site no volume e termina (o Caddy só serve arquivos).
CMD ["sh", "-c", "rm -rf /out/* && cp -r /web/. /out/ && echo 'site publicado'"]
