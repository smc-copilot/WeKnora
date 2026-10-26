#!/usr/bin/env bash
# smc-weknora 运维封装：固定项目名与编排文件，避免作用到本机其他服务。
# 用法: sudo /data/projects/weknora/deploy-docs/wk.sh <命令> [参数]
set -euo pipefail

ROOT=/data/projects/weknora
PROJECT=smc-weknora
COMPOSE=(docker compose -p "$PROJECT" -f docker-compose.yml -f deploy-docs/docker-compose.smc.yml)
SERVICES=(frontend app docreader postgres redis)

cd "$ROOT"

usage() {
  cat <<'EOF'
用法: wk.sh <命令> [服务] [参数]

状态
  ps                     容器状态
  health                 容器健康 + 网页/API 探活
  version                源码版本、镜像标签与 ID
  stats                  资源占用快照

日志
  logs [服务] [行数]     查看日志（默认全部服务、200 行）
  logs-f [服务]          实时跟随

生命周期
  up                     启动/创建（应用 .env 与覆盖文件变更）
  stop                   停止（保留容器与数据）
  start                  启动已停止的容器
  restart [服务]         重启
  recreate <服务>        按当前镜像重建单个容器（改 .env 后必用）
  down                   删除容器与网络（数据卷保留，绝不带 -v）

构建与备份
  build                  从源码重建 app/frontend/docreader
  backup                 备份数据库 + 文件 + 配置

示例
  sudo wk.sh logs docreader 100
  sudo wk.sh recreate app
EOF
}

need_svc() {
  [ $# -ge 1 ] || { echo "缺少服务名，可选: ${SERVICES[*]}" >&2; exit 2; }
  case " ${SERVICES[*]} " in *" $1 "*) ;; *) echo "未知服务: $1（可选: ${SERVICES[*]}）" >&2; exit 2;; esac
}

cmd="${1:-help}"
[ $# -gt 0 ] && shift

case "$cmd" in
  help|-h|--help) usage ;;

  ps)     "${COMPOSE[@]}" ps ;;

  health)
    for s in "${SERVICES[@]}"; do
      st=$(docker inspect -f '{{.State.Status}}{{if .State.Health}}/{{.State.Health.Status}}{{end}}' "smc-weknora-$s" 2>/dev/null || echo missing)
      printf '  %-28s %s\n' "smc-weknora-$s" "$st"
    done
    printf '  %-28s ' "app /health"
    docker exec smc-weknora-app curl -sf http://localhost:8080/health || echo FAIL
    WEB_BIND=$(grep -E '^WEKNORA_WEB_BIND=' .env | cut -d= -f2- || true)
    WEB_PORT=$(grep -E '^WEKNORA_WEB_PORT=' .env | cut -d= -f2- || true)
    WEB_BIND="${WEB_BIND:-127.0.0.1}"; WEB_PORT="${WEB_PORT:-18080}"
    printf '  %-28s ' "web $WEB_BIND:$WEB_PORT"
    curl -s -o /dev/null -w '%{http_code}\n' "http://$WEB_BIND:$WEB_PORT/"
    ;;

  version)
    echo "源码:      $(git -c safe.directory="$ROOT" -C "$ROOT" describe --tags --always)"
    echo "提交:      $(git -c safe.directory="$ROOT" -C "$ROOT" rev-parse HEAD)"
    tag=$(grep -E '^WEKNORA_VERSION=' .env | cut -d= -f2-)
    echo "镜像标签:  $tag"
    for i in wechatopenai/weknora-app wechatopenai/weknora-ui wechatopenai/weknora-docreader; do
      printf '  %-46s %s\n' "$i:$tag" "$(docker inspect -f '{{.Id}}' "$i:$tag" 2>/dev/null || echo missing)"
    done
    ;;

  stats) docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' | grep -E 'NAME|smc-weknora' ;;

  logs)
    if [ $# -ge 1 ]; then need_svc "$1"; svc="$1"; shift; else svc=""; fi
    n="${1:-200}"
    if [ -n "$svc" ]; then "${COMPOSE[@]}" logs --tail="$n" "$svc"; else "${COMPOSE[@]}" logs --tail="$n"; fi
    ;;

  logs-f)
    if [ $# -ge 1 ]; then need_svc "$1"; exec "${COMPOSE[@]}" logs -f --tail=200 "$1"; fi
    exec "${COMPOSE[@]}" logs -f --tail=200
    ;;

  up)       "${COMPOSE[@]}" up -d --no-build ;;
  stop)     "${COMPOSE[@]}" stop ;;
  start)    "${COMPOSE[@]}" start ;;
  restart)
    if [ $# -ge 1 ]; then need_svc "$1"; "${COMPOSE[@]}" restart "$1"; else "${COMPOSE[@]}" restart; fi
    ;;

  recreate)
    need_svc "${1:-}"
    "${COMPOSE[@]}" up -d --no-build --force-recreate --no-deps "$1"
    ;;

  down)
    for a in "$@"; do
      case "$a" in
        -v|--volumes) echo "拒绝: down 不允许带 $a（会删除数据卷）" >&2; exit 1;;
      esac
    done
    "${COMPOSE[@]}" down
    ;;

  build)  "${COMPOSE[@]}" build app frontend docreader ;;

  backup) exec "$ROOT/deploy-docs/backup.sh" ;;

  *) echo "未知命令: $cmd" >&2; usage; exit 2 ;;
esac