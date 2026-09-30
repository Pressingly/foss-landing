FROM nginx:1.27-alpine

COPY index.html.example /usr/share/landing/index.html.example
COPY docker-entrypoint.d/40-render-landing.sh /docker-entrypoint.d/40-render-landing.sh
RUN chmod 0755 /docker-entrypoint.d/40-render-landing.sh \
 && rm /usr/share/nginx/html/index.html

EXPOSE 80
