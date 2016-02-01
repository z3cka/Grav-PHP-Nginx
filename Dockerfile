FROM phusion/baseimage:0.9.16

MAINTAINER Ahumaro Mendoza <ahumaro@ahumaro.com>

CMD ["/sbin/my_init"]

ENV HOME /root
ENV DEBIAN_FRONTEND noninteractive

#Install core packages
RUN apt-get update -q
RUN apt-get upgrade -y 
RUN apt-get install -y -q php5 php5-cli php5-fpm php5-gd php5-curl php5-apcu ca-certificates nginx git-core
RUN apt-get clean -q && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#Get Grav
RUN rm -fR /usr/share/nginx/html/
RUN git clone https://github.com/getgrav/grav.git /usr/share/nginx/html/

#Install Grav
WORKDIR /usr/share/nginx/html/
RUN bin/composer.phar self-update
RUN bin/grav install
RUN chown www-data:www-data .
RUN chown -R www-data:www-data *
RUN find . -type f | xargs chmod 664
RUN find . -type d | xargs chmod 775
RUN find . -type d | xargs chmod +s
RUN umask 0002

#Configure Nginx - enable gzip
RUN sed -i 's|# gzip_types|  gzip_types|' /etc/nginx/nginx.conf

#Setup Grav configuration for Nginx
RUN touch /etc/nginx/grav_conf.sh
RUN touch /usr/share/nginx/html/nginx.conf
RUN chmod +x /usr/share/nginx/html/nginx.conf
RUN echo 'worker_processes  1; \n\
\n\
	events {\n\
	    worker_connections  1024;\n\
	}\n\
\n\
\n\
	http {\n\
	    include       mime.types;\n\
	    default_type  application/octet-stream;\n\
	    sendfile        on;\n\
	    keepalive_timeout  65;\n\
\n\
	    server {\n\
		listen       80;\n\
		server_name  localhost;\n\
\n\
		error_page   500 502 503 504  /50x.html;\n\
		location = /50x.html {\n\
		    root   html;\n\
		}\n\
\n\
		location / {\n\
			root   html;\n\
			index  index.php;\n\
			if (!-e $request_filename){ rewrite ^(.*)$ /index.php last; }\n\
		}\n\
\n\
		location /images/ {\n\
			# Serve images as static\n\
		}\n\
\n\
		location /user {\n\
			rewrite ^/user/accounts/(.*)$ /error redirect;\n\
			rewrite ^/user/config/(.*)$ /error redirect;\n\
			rewrite ^/user/(.*)\.(txt|md|html|php|yaml|json|twig|sh|bat)$ /error redirect;\n\
		}\n\
\n\
		location /cache {\n\
			rewrite ^/cache/(.*) /error redirect;\n\
		}\n\
\n\
		location /bin {\n\
			rewrite ^/bin/(.*)$ /error redirect;\n\
		}\n\
\n\
		location /backup {\n\
		rewrite ^/backup/(.*) /error redirect;\n\
		}\n\
\n\
		location /system {\n\
			rewrite ^/system/(.*)\.(txt|md|html|php|yaml|json|twig|sh|bat)$ /error redirect;\n\
		}\n\
\n\
		location /vendor {\n\
			rewrite ^/vendor/(.*)\.(txt|md|html|php|yaml|json|twig|sh|bat)$ /error redirect;\n\
		}\n\
\n\
		# Remember to change 127.0.0.1:9000 to the Ip/port\n\
		# you configured php-cgi.exe to run from\n\
\n\
		location ~ \.php$ {\n\
		    try_files $uri =404;\n\
		    fastcgi_split_path_info ^(.+\.php)(/.+)$;\n\
		    fastcgi_pass   127.0.0.1:9000;\n\
		    fastcgi_index  index.php;\n\
		    fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;\n\
		    include        fastcgi_params;\n\
		}\n\
\n\
	   }\n\
\n\
	}\n\' >> /usr/share/nginx/html/nginx.conf
RUN chmod +x /etc/nginx/grav_conf.sh
RUN echo '#!/bin/bash \n\
    echo "" > /etc/nginx/sites-available/default \n\
    ok="0" \n\
    while IFS="" read line \n\
    do \n\
        if [ "$line" = "    server {" ]; then \n\
            ok="1" \n\
        fi \n\
        if [ "$line" = "}" ]; then \n\
            ok="0" \n\
        fi \n\
        if [ "$ok" = "1" ]; then \n\
            echo "$line" >> /etc/nginx/sites-available/default \n\
        fi \n\
    done < /usr/share/nginx/html/nginx.conf' >> /etc/nginx/grav_conf.sh
RUN /etc/nginx/grav_conf.sh
RUN sed -i \
        -e 's|root   html|root   /usr/share/nginx/html|' \
        -e 's|127.0.0.1:9000;|unix:/var/run/php5-fpm.sock;|' \
    /etc/nginx/sites-available/default

#Setup Php service
RUN mkdir -p /etc/service/php5-fpm
RUN touch /etc/service/php5-fpm/run
RUN chmod +x /etc/service/php5-fpm/run
RUN echo '#!/bin/bash \n\
    exec /usr/sbin/php5-fpm -F' >> /etc/service/php5-fpm/run

#Setup Nginx service
RUN mkdir -p /etc/service/nginx
RUN touch /etc/service/nginx/run
RUN chmod +x /etc/service/nginx/run
RUN echo '#!/bin/bash \n\
    exec /usr/sbin/nginx -g "daemon off;"' >>  /etc/service/nginx/run

#Setup SSH service
RUN sed -i \
        -e 's|#PasswordAuthentication no|PasswordAuthentication no|' \
        -e 's|#UsePAM yes|UsePAM no|' \
    /etc/ssh/sshd_config
RUN rm -f /etc/service/sshd/down
RUN /etc/my_init.d/00_regen_ssh_host_keys.sh

#Expose configuration and content volumes
VOLUME /root/.ssh/ /etc/nginx/ /usr/share/nginx/html/

#get admin plugin and dependencies
RUN git clone https://github.com/getgrav/grav-plugin-admin.git /usr/share/nginx/html/user/plugins/grav-plugin-admin/
RUN git clone https://github.com/getgrav/grav-plugin-login.git /usr/share/nginx/html/user/plugins/grav-plugin-login/
RUN git clone https://github.com/getgrav/grav-plugin-email.git /usr/share/nginx/html/user/plugins/grav-plugin-email/
RUN git clone https://github.com/getgrav/grav-plugin-form.git /usr/share/nginx/html/user/plugins/grav-plugin-form

RUN ls /usr/share/nginx/html/user/plugins/

#change folder names to plugin names
RUN mv /usr/share/nginx/html/user/plugins/grav-plugin-admin/ /usr/share/nginx/html/user/plugins/admin/
RUN mv /usr/share/nginx/html/user/plugins/grav-plugin-login/ /usr/share/nginx/html/user/plugins/login/
RUN mv /usr/share/nginx/html/user/plugins/grav-plugin-email/ /usr/share/nginx/html/user/plugins/email/
RUN mv /usr/share/nginx/html/user/plugins/grav-plugin-form/ /usr/share/nginx/html/user/plugins/form/

#Public ports
EXPOSE 80 22
