@echo off

echo Building the Docker image...
docker build -t sql2019_alwayson .


set CONTAINER_NAME=my_sql_container

docker inspect %CONTAINER_NAME% >nul 2>&1
if %errorlevel% equ 0 (
    echo Container %CONTAINER_NAME% exists.
    REM Stop the container
    docker stop %CONTAINER_NAME%
	docker container rm %CONTAINER_NAME%
    echo Container %CONTAINER_NAME% stopped.
) else (
    echo Container %CONTAINER_NAME% does not exist.
)


echo Running the container in the background...
docker run -d -p 14333:1433 -it --name my_sql_container sql2019_alwayson

echo Waiting for the container to start...
timeout /t 10 /nobreak >nul

echo Executing SQL commands...
sqlcmd -S 127.0.0.1,14333 -U sa -P PaSSw0rd -i command.sql

echo Waiting for the container to start...
timeout /t 20 /nobreak >nul

echo Stopping the Docker container...
docker stop my_sql_container

echo Committing the container as a new image...
docker commit my_sql_container sql2019_alwayson_node
