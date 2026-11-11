#!/bin/sh
# geo-cron.sh enable|disable
# Manage the geo auto-update crontab entry. enable reads the schedule from
# daede.config.geo_auto_freq (daily|weekly); both actions are idempotent.

ACTION="$1"
CRONTAB="/etc/crontabs/root"
TAG="# luci-app-daede geo-update"
SCRIPT="/usr/share/luci-app-daede/update-geo.sh"

# Drop any previous daede geo entry (tag line + its command line).
clean() {
	[ -f "$CRONTAB" ] || return 0
	grep -vF -e "$TAG" -e "$SCRIPT" "$CRONTAB" > "$CRONTAB.tmp" 2>/dev/null
	mv "$CRONTAB.tmp" "$CRONTAB"
}

clean

if [ "$ACTION" = "enable" ]; then
	case "$(uci -q get daede.config.geo_auto_freq)" in
		# 路由器时区是 UTC。数据有变化时 daed 要重启、全屋断网约 1~2 秒，放在北京时间白天 10:17。
		weekly) sched="17 2 * * 0" ;;   # 北京时间周日 10:17（UTC 周日 02:17）
		*)      sched="17 2 * * *" ;;   # 北京时间每天 10:17（UTC 02:17）
	esac
	mkdir -p /etc/crontabs
	{
		echo "$TAG"
		echo "$sched $SCRIPT geoip; $SCRIPT geosite"
	} >> "$CRONTAB"
	/etc/init.d/cron enable >/dev/null 2>&1
fi

/etc/init.d/cron restart >/dev/null 2>&1
exit 0
