#!/bin/env bash

#------------------------------------------------------------------------------------------------------------------------------------------------------

IP=$(curl -s --connect-timeout 2 ifconfig.co)
PORT=65530
UUID=$(uuidgen)
WEBPATH=/opendoor
VERSION=v4.28.2
PREFIX=/apps/v2ray
V_CONF=${PREFIX}/config.json
N_CONF=/apps/nginx/conf/nginx.conf
SVC=/usr/lib/systemd/system
GITHUB=https://raw.githubusercontent.com/rong280
SLACK=https://hooks.slack.com/xxxxxxxxxxxxxxxxx && GROUP=xxxx

#--------------------------------------------------------------------------------------------------------------------------------------------------------

check_system(){
    source /etc/os-release
        if [ $ID = centos ];then
                if [[ $VERSION_ID != [78] ]];then
                        echo 此脚本仅支持CentOS7和8
                        exit
                fi
            else
                    echo 此脚本仅支持CentOS7和8
        fi
}

#--------------------------------------------------------------------------------------------------------------------------------------------------------

create_ssl(){
	command -v openssl &> /dev/null || yum -y install openssl
	SSLPATH=/apps/nginx/conf/.certs
	mkdir ${SSLPATH}
	openssl ecparam -genkey -name prime256v1 -out you.key
	openssl req -new -sha384 -key you.key -out you.csr -subj "/C=CN/ST=GD/L=SZ/CN=${IP}"
	openssl x509 -req -days 365 -in you.csr -signkey you.key -out you.crt
	rm -rf *.csr
	mv you.* ${SSLPATH}/
}

Compile_install(){
    ./configure --prefix=/apps/nginx \
    --user=nginx \
    --group=nginx \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-pcre \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-http_perl_module
}

nginx_install(){
    yum -y install gcc gcc-c++ pcre-devel openssl-devel zlib-devel make perl-devel perl-ExtUtils-Embed wget || { echo 安装失败,请检查yum源;exit; }
    wget -c -P /usr/local/src http://nginx.org/download/nginx-1.18.0.tar.gz || { echo 下载失败,请检查网络后重新执行脚本;exit; }
    tar xf /usr/local/src/nginx-1.18.0.tar.gz -C /usr/local/src

    SPATH=/usr/local/src/nginx-1.18.0
    cd $SPATH
    sed -i -e '/NGINX_VERSION/s/1.18.0/6.6.6/' -e '/NGINX_VERSION/s/nginx/Apache/' src/core/nginx.h
    sed -i '/Server: nginx/s/nginx/Apache/' src/http/ngx_http_header_filter_module.c
    sed -i '/>nginx</s/nginx/Apache/' src/http/ngx_http_special_response.c


    Compile_install
    make -j $(lscpu | awk '/^CPU\(/{print $2}')
    STATUS=$?
        if [ $STATUS = 0 ];then
                make install
            elif [ $STATUS = 2 ];then
                    make clean
                    Compile_install
                    sed -i -r '/^(CFLAGS|NGX_PERL_CFLAGS|NGX_PM_CFLAGS)/s/=/= -fPIC/' objs/Makefile
                    make -j $(lscpu | awk '/^CPU\(/{print $2}') && make install || { rm -rf $SPATH;echo 编译失败请查看报错信息;exit; }
            else
                    rm -rf $SPATH
                    echo 编译失败，脚本无法处理，请查看报错信息
                    exit
        fi

    id nginx &> /dev/null || { groupadd nginx;useradd -M -g nginx -s /sbin/nologin nginx; }
        [ ! -f /usr/sbin/nginx ] && ln -s /apps/nginx/sbin/nginx /usr/sbin/nginx
    curl -so ${N_CONF} ${GITHUB}/Hello-World/main/conf/nginx.conf
    rm -rf /apps/nginx/html
    chown -R nginx.nginx /apps/nginx
    rm -rf $SPATH
	cat > ${SVC}/nginx.service<<-EOF
	[Unit]
	Description=nginx - high performance web server
	Documentation=http://nginx.org/en/docs/
	After=network-online.target remote-fs.target nss-lookup.target
	Wants=network-online.target

	[Service]
	Type=forking
	PIDFile=/apps/nginx/logs/nginx.pid
	ExecStart=/apps/nginx/sbin/nginx -c ${N_CONF}
	ExecReload=/sbin/nginx -s reload
	ExecStop=/sbin/nginx -s stop

	[Install]
	WantedBy=multi-user.target
	EOF

	create_ssl
}

#--------------------------------------------------------------------------------------------------------------------------------------------------

read_file(){
	curl -so ${V_CONF} ${GITHUB}/Hello-World/main/conf/config.json
	sed -i "s/PORT/${PORT}/;s/UUID/${UUID}/;s@WEBPATH@/${WEBPATH}@" ${V_CONF}
	cp ${PREFIX}/systemd/system/v2ray.service ${SVC}/
	sed -ri 's@(Start=).*(-config).*(config.json)@\1/apps/v2ray/v2ray \2 /apps/v2ray/\3@' ${SVC}/v2ray.service
	systemctl daemon-reload
	mkdir -p /var/log/v2ray
	chown nobody.nobody /var/log/v2ray
}

install_v2ray(){
	for c in wget unzip jq
	do
		command -v $c || yum -y install $c
	done

	if [ ! -f ${PREFIX}/v2ray-linux-64.zip ];then
		wget -c -P ${PREFIX} https://github.com/v2ray/v2ray-core/releases/download/$VERSION/v2ray-linux-64.zip || { echo '下载失败，请检查网络后重试！';exit; }
		unzip ${PREFIX}/v2ray-linux-64.zip -d ${PREFIX}
		read_file
	elif [ -f ${PREFIX}/v2ray-linux-64.zip ];then
		unzip ${PREFIX}/v2ray-linux-64.zip -d ${PREFIX}
		read_file
	fi

	if [[ ${ws} == [Yy] ]];then
		systemctl enable --now v2ray nginx &> /dev/null
		clear
		systemctl status v2ray nginx
	else
		systemctl enable --now v2ray
		clear
		systemctl status v2ray
	fi

	echo && echo -e "\033[32mIP：${IP}\nPORT：${PORT}\nUUID：${UUID}\nPATH：${WEBPATH}\033[0m"
}

#--------------------------------------------------------------------------------------------------------------------------------------------------

uninstall(){
	rm -rf /apps/v2ray
	rm -rf /var/log/v2ray
	rm -rf ${SVC}/v2ray.service
	echo -e "${RED}卸载完毕${COLOREND}"
}

#--------------------------------------------------------------------------------------------------------------------------------------------------

vmess(){
	PORT=$(jq '.inbounds[0].port' ${V_CONF})
	ID=$(jq -r '.inbounds[0].settings.clients[0].id' ${V_CONF})
	ALTERID=$(jq -r '.inbounds[0].settings.clients[0].alterId' ${V_CONF})
	
	vmess=vmess://$(base64 -w 0 <<-EOF
	{
	  "v": "2",
	  "ps": "Singapore",
	  "add": "$IP",
	  "port": "$PORT",
	  "id": "$ID",
	  "aid": "$ALTERID",
	  "net": "tcp",
	  "type": "none",
	  "host": "",
	  "path": "",
	  "tls": ""
	}
	EOF
	)
}

#--------------------------------------------------------------------------------------------------------------------------------------------------

manager(){
	echo
	#cat <<-EOF
	echo -e "${GREEN}
--------------------------------------------

          0. 更换端口
          1. 更换WEB_URL
          2. 更换UUID（随机）
          3. 打印配置信息
	  4. 将配置发送到Slack
          5. 安装
          6. ${REDH}卸载${COLOREND}"
	echo -e "${GREEN}          7. 退出脚本

--------------------------------------------
	${COLOREND}"
	#EOF
	
	echo
	read -p "请输入数字 [0-6]：" num

	case $num in
		0)
			echo
			read -p "请输入端口号：" ports
			sed -ri "/\"port\"/s/[0-9]+/${ports}/" ${V_CONF}
			sed -ri "s/(0.1:).*/\1${ports};/" ${N_CONF}
			systemctl restart v2ray nginx
			manager
		;;
		1)
			echo
			read -p "请输入你的URL：" url
			sed -ri "s@(\"path\": \").*(\")@\1${url}\2@" ${V_CONF}
			sed -ri "s@(location ).*( \{)@\1${url}\2@" ${N_CONF}
			systemctl restart v2ray nginx
			manager
		;;
		2)
			echo
			sed -ri "s/(id\": \").*(\",)/\1$(uuidgen)\2/" ${V_CONF}
			sed -nr 's/"id": "(.*)",/\1/p' ${V_CONF}
			systemctl restart v2ray
			manager
		;;
		3)
			echo && echo 配置链接:
			vmess
			echo $vmess
			manager
		;;
		4)
			echo
			vmess
			curl -X POST --data-urlencode "payload={\"channel\": \"#$GROUP\", \"username\": \"v2ray\", \"text\": \"$vmess\", \"icon_emoji\": \":ghost:\"}" $SLACK
			manager
		;;
		5)
			echo
			read -p '是否使用WebSocket+TLS+Nginx对流量进行伪装？[y/n]：' ws
			if [[ ${ws} == [Yy] ]];then
				command -v nginx &> /dev/null && echo -e "${RED}检测到您已安装Nginx,需要手动配置反向代理！${COLOREND}" || nginx_install
			fi
			[ -f ${SVC}/v2ray.service ] && echo -e "${GREEN}检测到已安装 v2ray${COLOREND}" || install_v2ray
			manager
		;;
		6)
			echo
			echo -e "10秒后开始卸载,如需取消卸载请按：${RED}Ctrl+C${COLOREND}"
			sleep 10
			systemctl stop v2ray
			uninstall
			manager
		;;
		7)
			exit
		;;
		*)
			echo && echo "请输入正确的数字 [0-3]"
			sleep 2
			manager
		;;
	esac
	
}

#----------------------------------------------------------------------------------------------------------------------------------------------

source <(curl -s --connect-timeout 3 ${GITHUB}/ShellScript/main/start.sh)
v2ray
manager
