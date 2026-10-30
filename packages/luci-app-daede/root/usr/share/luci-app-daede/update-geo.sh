#!/bin/sh
# update-geo.sh <geoip|geosite>
# Fork-and-detach so the LuCI RPC call returns immediately. The diagnostics
# card polls the .dat file's mtime/size to detect completion. A lock file
# in /tmp prevents concurrent runs.
#
# daed 掉线等于全屋断网，所以新文件必须验明才替换：结构完整、含路由规则用到的全部分类，
# 内容没变就什么都不做；重启后 daed 没有完成绑定，就换回旧文件再重启一次。
# 用 restart 而不是 reload：daed.init 没有 reload_service，reload 不会让 daed 重读数据。

TYPE="$1"
# Default source: the v2fly projects, same origin as the official v2ray-geodata
# packages. Users can override per-type via daede.config.geoip_url / geosite_url.
case "$TYPE" in
	geoip)
		DEF_URL="https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
		URL="$(uci -q get daede.config.geoip_url)"
		DEST="/usr/share/v2ray/geoip.dat"
		TAGS="CN,PRIVATE"
		;;
	geosite)
		DEF_URL="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
		URL="$(uci -q get daede.config.geosite_url)"
		DEST="/usr/share/v2ray/geosite.dat"
		TAGS="CN,GEOLOCATION-!CN,CATEGORY-AI-!CN,CATEGORY-AI-CN,ANTHROPIC,OPENAI"
		;;
	*)
		echo "usage: $0 <geoip|geosite>" >&2
		exit 64
		;;
esac
[ -n "$URL" ] || URL="$DEF_URL"

LOCK="/tmp/luci-app-daede.${TYPE}.lock"
LOG="/tmp/luci-app-daede.${TYPE}.log"
RLOCK="/tmp/luci-app-daede.geo-reload.lock"
DAED_LOG="/var/log/daed/daed.log"
DB_BAK="/tmp/luci-app-daede.wing.db"

# 顶层是一串 GeoIP/GeoSite 条目（field 1，LEN），每条的第一个字段是分类名。
# 走完全部条目能发现截断，再确认规则引用的分类都在。
valid_dat() { # valid_dat <文件> <逗号分隔的分类>
	ucode -e '
		let fs = require("fs"), d = fs.readfile(ARGV[0]), n = length(d), i = 0, tags = {};
		function uv() {
			let v = 0, s = 0;
			while (i < n) {
				let c = ord(d, i++);
				v += (c & 127) * (1 << s);
				s += 7;
				if (c < 128) return v;
				if (s > 35) exit(1);
			}
			exit(1);
		}
		while (i < n) {
			if (ord(d, i++) != 10) exit(1);
			let e = uv() + i;
			if (e > n || ord(d, i++) != 10) exit(1);
			let l = uv();
			tags[uc(substr(d, i, l))] = true;
			i = e;
		}
		for (let t in split(ARGV[1], ","))
			if (!tags[t]) exit(2);
	' -- "$1" "$2"
}

daed_bound() {
	i=0
	while [ "$i" -lt 90 ]; do
		/bin/pidof daed >/dev/null 2>&1 && grep -q "Bind to LAN" "$DAED_LOG" 2>/dev/null && return 0
		sleep 3
		i=$((i + 3))
	done
	return 1
}

schedule_backend_reload() {
	if [ -d "$RLOCK" ]; then
		rmt=$(date -r "$RLOCK" +%s 2>/dev/null || echo 0)
		[ $(( $(date +%s) - rmt )) -gt 300 ] && rmdir "$RLOCK" 2>/dev/null
	fi
	mkdir "$RLOCK" 2>/dev/null || return 0
	(
		sleep 25
		if /bin/pidof daed >/dev/null 2>&1; then
			# 数据加载失败时 dae-wing 会把"运行中"状态清掉，之后重启只有空配置，
			# 所以数据库也要留一份，回滚时一起换回。
			( umask 077; cp -f /etc/daed/wing.db "$DB_BAK" )
			/etc/init.d/daed restart >/dev/null 2>&1
			if daed_bound; then
				rm -f /usr/share/v2ray/*.dat.bak "$DB_BAK"
				echo "$(date '+%F %T') reloaded daed"
			else
				/etc/init.d/daed stop >/dev/null 2>&1
				sleep 3
				for f in /usr/share/v2ray/*.dat.bak; do
					[ -f "$f" ] && mv "$f" "${f%.bak}"
				done
				mv -f "$DB_BAK" /etc/daed/wing.db
				/etc/init.d/daed start >/dev/null 2>&1
				if daed_bound; then
					echo "$(date '+%F %T') new data broke daed, rolled back"
				else
					echo "$(date '+%F %T') daed failed after rollback"
				fi
			fi
		else
			rm -f /usr/share/v2ray/*.dat.bak
			echo "$(date '+%F %T') daed not running; skip reload"
		fi
		rmdir "$RLOCK" 2>/dev/null
	) </dev/null >>"$LOG" 2>&1 &
}

if [ -f "$LOCK" ]; then
	# Lock is fresh (< 5 min)? Refuse. Stale? Remove and proceed.
	mtime=$(date -r "$LOCK" +%s 2>/dev/null || echo 0)
	age=$(( $(date +%s) - mtime ))
	if [ "$age" -lt 300 ]; then
		echo "${TYPE} update already in progress (PID $(cat "$LOCK" 2>/dev/null), age ${age}s)" >&2
		exit 75
	fi
	rm -f "$LOCK"
fi

if ! ( set -C; echo "$$" >"$LOCK" ) 2>/dev/null; then
	echo "${TYPE} update already in progress" >&2
	exit 75
fi

# Spawn detached worker — parent returns immediately to LuCI.
(
	exec >"$LOG" 2>&1
	trap 'rm -f "$LOCK"' EXIT INT TERM

	rc=0
	TMP="${DEST}.new"
	mkdir -p "$(dirname "$DEST")"
	echo "$(date '+%F %T') begin: $URL"

	if ! curl -fsSL --connect-timeout 15 --max-time 240 -o "$TMP" "$URL"; then
		echo "$(date '+%F %T') download failed"
		rm -f "$TMP"
		rc=1
	elif ! valid_dat "$TMP" "$TAGS"; then
		echo "$(date '+%F %T') invalid geodata, keeping the current file"
		rm -f "$TMP"
		rc=2
	elif cmp -s "$TMP" "$DEST"; then
		echo "$(date '+%F %T') already up to date"
		rm -f "$TMP"
	else
		cp -f "$DEST" "$DEST.bak"
		mv "$TMP" "$DEST"
		echo "$(date '+%F %T') updated $DEST ($(wc -c < "$DEST") bytes)"
		schedule_backend_reload
	fi
	if [ "$rc" = 0 ]; then echo "$(date '+%F %T') ✓ 完成"; else echo "$(date '+%F %T') ✗ 失败 (rc=$rc)"; fi
) </dev/null >/dev/null 2>&1 &

echo "started in background, see $LOG"
exit 0
