#!/bin/sh
set -eu
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"
if [ ! -f backend/artisan ]; then
  mkdir -p backend
  docker run --rm -v "$(pwd)/backend:/app" -w /app composer:2 sh -c 'composer create-project laravel/laravel /tmp/signflow --no-interaction && cp -a /tmp/signflow/. /app/'
fi
docker compose build api
docker compose run --rm --no-deps api composer require laravel/sanctum --no-interaction
cp -r laravel-overlay/app/. backend/app/
cp -r laravel-overlay/database/migrations/. backend/database/migrations/
cp laravel-overlay/routes/api.php backend/routes/api.php
cp laravel-overlay/bootstrap_app.php backend/bootstrap/app.php
# Add companies relation to User without overwriting Laravel defaults.
python3 - <<'PY'
p='backend/app/Models/User.php'
s=open(p).read()
if 'function companies()' not in s:
 idx=s.rfind('}')
 s=s[:idx]+'''    public function companies() { return $this->belongsToMany(\\App\\Models\\Company::class)->withPivot('role')->withTimestamps(); }
'''+s[idx:]
 open(p,'w').write(s)
PY
cat >> backend/.env <<'ENV'
DB_CONNECTION=pgsql
DB_HOST=db
DB_PORT=5432
DB_DATABASE=signflow
DB_USERNAME=signflow
DB_PASSWORD=local_dev_password
ENV
docker compose up -d db
docker compose run --rm api php artisan migrate --force
printf '\nSetup OK. Run: docker compose up -d api flutter\n'

