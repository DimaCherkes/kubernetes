FROM nginx:1.27-alpine

# Remove default nginx configuration and html assets
RUN rm -rf /usr/share/nginx/html/* /etc/nginx/conf.d/*

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy static frontend assets into Nginx webroot
COPY src/ /usr/share/nginx/html/

# Symlink src directory to webroot to support paths like /src/styles.css seamlessly
RUN ln -s /usr/share/nginx/html /usr/share/nginx/html/src

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
