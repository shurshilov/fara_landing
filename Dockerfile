### Stage 1: Build — minify HTML/CSS, optimize images ###
FROM node:20-alpine AS build

WORKDIR /app

# Install minifiers
RUN npm i -g html-minifier-terser clean-css-cli

# Copy source
COPY index.html ./
COPY vs/ ./vs/
COPY styles/ ./styles/
COPY scripts/ ./scripts/
COPY fonts/ ./fonts/
COPY images/ ./images/

# Create dist
RUN mkdir -p dist/styles dist/scripts dist/fonts dist/images

# Minify HTML
RUN html-minifier-terser \
    --collapse-whitespace \
    --remove-comments \
    --minify-css true \
    --minify-js true \
    -o dist/index.html \
    index.html

# Minify comparison pages (vs/<name>/index.html)
RUN for d in vs/*/; do \
      mkdir -p "dist/$d"; \
      html-minifier-terser \
        --collapse-whitespace \
        --remove-comments \
        --minify-css true \
        --minify-js true \
        -o "dist/${d}index.html" \
        "${d}index.html"; \
    done

# Minify CSS
RUN for f in styles/*.css; do \
      cleancss -o "dist/$f" "$f"; \
    done

# Copy scripts, fonts and images as-is
RUN cp -r scripts/* dist/scripts/ && \
    cp -r fonts/* dist/fonts/ && \
    cp -r images/* dist/images/

### Stage 2: Serve with nginx ###
FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*

COPY --from=build /app/dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

HEALTHCHECK --interval=30s --timeout=3s \
    CMD wget -qO- http://localhost/ || exit 1

EXPOSE 80
