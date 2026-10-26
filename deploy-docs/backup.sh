#!/usr/bin/env bash
# WeKnora(smc-weknora) 一致性备份：数据库 + 上传文件 + 配置。
# 用法: sudo /data/projects/weknora/deploy-docs/backup.sh
# 产物: /data/backups/weknora/<时间戳>/  (默认保留最近 14 份)
set -euo pipefail

ROOT=/data/projects/weknora
PROJECT=smc-weknora
DEST_BASE=/data/backups/weknora
KEEP=14
cd "$ROOT"

TS=$(date +%Y%m%d-%H%M%S)
DEST="$DEST_BASE/$TS"
mkdir -p "$DEST"
chmod 700 "$DEST_BASE"

echo "[1/4] 数据库逻辑备份（pg_dump -Fc，事务一致）"
docker exec smc-weknora-postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$DEST/weknora.dump"
echo "      $(du -h "$DEST/weknora.dump" | cut -f1)"

echo "[2/4] 上传文件与解析产物"
tar -C /var/lib/docker/volumes/smc-weknora-data-files/_data -czf "$DEST/data-files.tar.gz" .
echo "      $(du -h "$DEST/data-files.tar.gz" | cut -f1)"

echo "[3/4] 配置（含 .env，权限 600）"
install -m 600 .env "$DEST/.env"
install -m 644 docker-compose.yml "$DEST/docker-compose.yml"
install -m 644 deploy-docs/docker-compose.smc.yml "$DEST/docker-compose.smc.yml"
install -m 644 config/config.yaml "$DEST/config.yaml"
git -c safe.directory="$ROOT" -C "$ROOT" rev-parse HEAD > "$DEST/GIT_COMMIT"
grep -E '^WEKNORA_VERSION=' .env > "$DEST/VERSION"

echo "[4/4] 校验和与清单"
( cd "$DEST" && sha256sum weknora.dump data-files.tar.gz .env docker-compose.yml docker-compose.smc.yml config.yaml GIT_COMMIT > SHA256SUMS )
chmod -R go-rwx "$DEST"

echo "完成: $DEST"
echo
echo "注意："
echo "  - .env 含 JWT/AES 密钥，必须与数据库备份一起保管；SYSTEM_AES_KEY 丢失则库内密文不可解。"
echo "  - 文件备份在业务写入过程中打包，正在上传的单个文件可能不完整；严格一致请先 wk.sh stop。"
echo "  - Redis 中的队列/流状态未备份，恢复后未完成的解析任务需要重新触发。"

if [ -d "$DEST_BASE" ]; then
  ls -1dt "$DEST_BASE"/*/ 2>/dev/null | tail -n +$((KEEP+1)) | while read -r old; do
    echo "清理旧备份: $old"; rm -rf -- "$old"
  done
fi
