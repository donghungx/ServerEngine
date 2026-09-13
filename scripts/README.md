chmod +x scripts/build_php_runtime.sh


scripts/build_php_runtime.sh --version 8.5.0 --overwrite

chmod +x scripts/runtime_uploader_gui.py
python3 scripts/runtime_uploader_gui.py

chmod +x scripts/install_database_runtime.sh
scripts/install_database_runtime.sh --formula mariadb --overwrite
scripts/install_database_runtime.sh --formula mariadb@11.4 --overwrite
scripts/install_database_runtime.sh --formula mysql --overwrite

chmod +x scripts/install_redis_runtime.sh
scripts/install_redis_runtime.sh --formula redis --overwrite

chmod +x scripts/install_apache_runtime.sh
scripts/install_apache_runtime.sh --overwrite

chmod +x scripts/install_nginx_runtime.sh
scripts/install_nginx_runtime.sh --formula nginx --overwrite

chmod +x scripts/install_phpmyadmin.sh
scripts/install_phpmyadmin.sh --version 5.2.2 --overwrite

chmod +x scripts/build_macos_app.sh
scripts/build_macos_app.sh

chmod +x scripts/build_macos_pkg.sh
scripts/build_macos_pkg.sh

chmod +x scripts/build_macos_uninstall_pkg.sh
scripts/build_macos_uninstall_pkg.sh --clean




Production note:
  The packaged output should be copied by your installer into the app-managed
  runtime root, for example:

    ~/Library/Application Support/Server Engine/bin/php/php8.5.0
