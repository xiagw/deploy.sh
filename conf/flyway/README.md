## default use docker
docker pull flyway/flyway

## default use root for database username

## change flyway.conf: database.ip/database.name/root.password

## create folder "docs/sql" in your git repository
mkdir <your_git_dir>/docs/sql
vi <your_git_dir>/docs/sql/V1.0__base_structure.sql
git add .
git commit -m 'add sql'