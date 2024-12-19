#!/bin/bash
# Прекращаем выполнение при ошибке
set -e

clear
echo "============================================"
echo "WordPress Install Script"
echo "============================================"

# Вводим параметры для базы данных
echo "Введите название базы данных: "
read dbname
echo "Введите пользователя базы данных: "
read dbuser
echo "Введите пароль базы данных: "
read -s dbpass

# Подтверждаем запуск установки
echo "Запустить установку? (y/n)"
read run

if [ "$run" = "n" ]; then
    exit
else
    echo "============================================"
    echo "Автоматическая установка WordPress."
    echo "============================================"

    # Скачиваем последнюю версию WordPress
    curl -O https://wordpress.org/latest.tar.gz

    # Распаковываем архив
    tar -zxvf latest.tar.gz

    # Переходим в каталог WordPress
    cd wordpress

    # Копируем файлы WordPress в текущую директорию (обычно в веб-корень)
    cp -rf . ..

    # Возвращаемся в родительский каталог
    cd ..

    # Удаляем папку с WordPress, она больше не нужна
    rm -rf wordpress

    # Создаём файл wp-config.php на основе wp-config-sample.php
    cp wp-config-sample.php wp-config.php

    # Замена стандартных значений базы данных на введённые данные
    sed -i "s/database_name_here/$dbname/" wp-config.php
    sed -i "s/username_here/$dbuser/" wp-config.php
    sed -i "s/password_here/$dbpass/" wp-config.php

    # Генерируем уникальные ключи безопасности для WordPress
    curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php

    # Создаём папку uploads и задаём правильные права доступа
    mkdir -p wp-content/uploads
    chmod 775 wp-content/uploads

    echo "============================================"
    echo "WordPress установлен успешно!"
    echo "============================================"
   
    # Очистка
    rm latest.tar.gz
fi
