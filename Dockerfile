FROM buildpack-deps:jessie
MAINTAINER Eugene Ware <eugene@noblesamurai.com>

RUN apt-get update
RUN apt-get install -y locales apache2-bin apache2-dev apache2.2-common --no-install-recommends  
RUN apt-get install -y curl libmcrypt-dev git libxml2-dev nano libgd-dev libfreetype6-dev libjpeg62-turbo-dev libpng12-dev
RUN apt-get install -y libc-client-dev

RUN echo America\La_Paz > /etc/timezone && dpkg-reconfigure --frontend noninteractive tzdata

RUN echo 'es_BO ISO-8859-1'\
>> /etc/locale.gen &&  \
usr/sbin/locale-gen

RUN rm -rf /var/www/html && mkdir -p /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html && chown -R www-data:www-data /var/lock/apache2 /var/run/apache2 /var/log/apache2 /var/www/html

# Apache + PHP requires preforking Apache for best results
RUN a2dismod mpm_event && a2enmod mpm_prefork

RUN mv /etc/apache2/apache2.conf /etc/apache2/apache2.conf.dist
COPY apache2.conf /etc/apache2/apache2.conf

ENV GPG_KEYS \
	DFFA3DCF326E302C4787673A01C4E7FAAAB2461C \
	42F3E95A2C4F08279C4960ADD68FA50FEA312927 \
	492EAFE8CD016A07919F1D2B9ECBEC467F0CEB10
RUN set -ex \
	&& for key in $GPG_KEYS; do \
	apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done

# compile openssl, otherwise --with-openssl won't work
RUN CFLAGS="-fPIC" && OPENSSL_VERSION="1.0.2d" \
      && cd /tmp \
      && mkdir openssl \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
      && gpg --verify openssl.tar.gz.asc \
      && tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
      && cd /tmp/openssl \
      && ./config shared && make && make install \
      && rm -rf /tmp/*

ENV PHP_VERSION 5.3.29

ENV PHP_INI_DIR /usr/local/lib
RUN mkdir -p $PHP_INI_DIR/conf.d

# php 5.3 needs older autoconf
RUN set -x \
	&& apt-get update && apt-get install -y autoconf2.13 libpng-dev zlib1g-dev  zip && rm -r /var/lib/apt/lists/* \
	&& curl -SLO http://launchpadlibrarian.net/140087283/libbison-dev_2.7.1.dfsg-1_amd64.deb \
	&& curl -SLO http://launchpadlibrarian.net/140087282/bison_2.7.1.dfsg-1_amd64.deb \
	&& dpkg -i libbison-dev_2.7.1.dfsg-1_amd64.deb \
	&& dpkg -i bison_2.7.1.dfsg-1_amd64.deb \
	&& rm *.deb \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.bz2/from/this/mirror" -o php.tar.bz2 \
	&& curl -SL "http://php.net/get/php-$PHP_VERSION.tar.bz2.asc/from/this/mirror" -o php.tar.bz2.asc \
	&& gpg --verify php.tar.bz2.asc \
	&& mkdir -p /usr/src/php \
	&& tar -xf php.tar.bz2 -C /usr/src/php --strip-components=1 \
	&& rm php.tar.bz2* \
	&& cd /usr/src/php \
	&& ./buildconf --force \
	&& ./configure --disable-cgi \
		$(command -v apxs2 > /dev/null 2>&1 && echo '--with-apxs2' || true) \
    --with-config-file-path="$PHP_INI_DIR" \
    --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		--with-mysql \
		--with-mysqli \
		--with-pdo-mysql \
		--with-gd \
		--with-openssl=/usr/local/ssl \
	&& make -j"$(nproc)" \
	&& make install \
	&& dpkg -r bison libbison-dev && make clean

COPY docker-php-* /usr/local/bin/
COPY apache2-foreground /usr/local/bin/

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer 
RUN docker-php-ext-install zip 
RUN docker-php-ext-install mbstring 
RUN docker-php-ext-install pdo 
RUN docker-php-ext-install pdo_mysql 
RUN docker-php-ext-install mysql 
RUN docker-php-ext-install json 
RUN docker-php-ext-install curl 
RUN docker-php-ext-install fileinfo 
#RUN docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ 
RUN docker-php-ext-install gd
#RUN docker-php-ext-install -j$(nproc) gd
RUN docker-php-ext-configure imap --with-kerberos --with-imap-ssl 
RUN docker-php-ext-install imap
RUN docker-php-ext-install mcrypt

RUN  cp /usr/src/php/php.ini-production /usr/local/lib/php.ini
# FFmpeg libx264 - H.264 encodeR

RUN git clone --depth 1 git://git.videolan.org/x264 && \
	cd x264 && \
	config_make --enable-static && \
	cd .. && rm -rf x264

# updated libtool for libfdk_aac
RUN yum -y install texinfo help2man xz patch
RUN git clone --depth 1 git://git.savannah.gnu.org/libtool.git && \
	cd libtool && \
	./bootstrap && \
	config_make && \
	cd .. && rm -rf libtool

# libfdk_aac - AAC encoder
RUN git clone --depth 1 git://git.code.sf.net/p/opencore-amr/fdk-aac && \
	cd fdk-aac && \
	autoreconf -fiv && \
	config_make --disable-shared && \
	cd .. && rm -rf fdk-aac

# libmp3lame - MP3 encoder
RUN curl -L -O http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz && \
	tar xzvf lame-3.99.5.tar.gz && \
	      cd lame-3.99.5        && \
	config_make --disable-shared --enable-nasm && \
	cd .. && rm -rf lame-*

# FFmpeg
#--enable-libx264 --enable-libfdk_aac --enable-libmp3lame \ 
#--enable-libvorbis --enable-libvpx \
RUN git clone --depth 1 git://source.ffmpeg.org/ffmpeg && \
	cd ffmpeg && \
	config_make --enable-gpl --enable-nonfree \
		--enable-libopus && \
	cd .. && rm -rf ffmpeg
RUN apt-get purge -y --auto-remove autoconf2.13 
RUN rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

EXPOSE 80
CMD ["apache2-foreground"]
