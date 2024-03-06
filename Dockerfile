FROM ubuntu:18.04
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get install apt-utils -y

RUN apt-get install sudo wget curl gnupg gnupg1 gnupg2 -y
RUN apt-get install software-properties-common systemd vim -y
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

RUN add-apt-repository "$(wget -qO- https://packages.microsoft.com/config/ubuntu/18.04/mssql-server-2019.list)"
RUN apt-get update
RUN apt-get install -y mssql-server

RUN /opt/mssql/bin/mssql-conf set hadr.hadrenabled  1
RUN /opt/mssql/bin/mssql-conf set sqlagent.enabled true

EXPOSE 1433
EXPOSE 5022

ENV ACCEPT_EULA=Y
ENV SA_PASSWORD="PaSSw0rd"
ENV MSSQL_PID=Developer

WORKDIR /usr/

ENTRYPOINT /opt/mssql/bin/sqlservr

