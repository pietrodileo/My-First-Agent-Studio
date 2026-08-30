FROM docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.3.0AI.136.0
ENV IRISUSERNAME=_SYSTEM IRISPASSWORD=SYS IRISNAMESPACE=FIRST_AGENT
ENV PATH=/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin
WORKDIR /home/irisowner/dev
COPY requirements-mcp.txt ./requirements-mcp.txt
COPY merge.cpf App.Installer.cls iris.script ./
COPY --chown=irisowner:irisowner mcp-python-server.py ./mcp-python-server.py
COPY --chown=irisowner:irisowner --chmod=0755 src ./src
COPY --chown=irisowner:irisowner data ./data
RUN python3 -m venv /home/irisowner/.venvs/mcp-tools && \
    /home/irisowner/.venvs/mcp-tools/bin/python -m pip install \
      --requirement /home/irisowner/dev/requirements-mcp.txt \
      --target /usr/irissys/mgr/python
RUN iris start IRIS && iris merge IRIS merge.cpf && iris session IRIS < iris.script && iris stop IRIS quietly
EXPOSE 1972 52773
