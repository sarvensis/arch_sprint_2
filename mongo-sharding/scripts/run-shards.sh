#!/bin/bash

wait_for_service() {
  local service=$1
  local port=$2
  until docker-compose exec -T $service mongosh --port $port --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
    echo "Ожидание готовности $service на порту $port..."
    sleep 2
  done
  echo "$service is ready!"
}

wait_for_service "configSrv" 27017
echo "Инициализация Config Server Replica Set..."
docker-compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
    _id : "config_server",
    configsvr: true,
    members: [
        { _id : 0, host : "configSrv:27017" }
    ]
})
EOF
echo "Инициализация Config Server Replica Set..."


wait_for_service "shard1" 27018
echo "Инициализация Shard1..."
docker-compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
    _id: "shard1",
    members: [{ _id: 0, host: "shard1:27018" }]
});
EOF

wait_for_service "shard2" 27019
echo "Инициализация Shard2..."
docker-compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
    _id: "shard2",
    members: [{ _id: 1, host: "shard2:27019" }]
});
EOF

wait_for_service "mongos_router" 27020
echo "Инициализация Роутера..."
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard( "shard1/shard1:27018");
sh.addShard( "shard2/shard2:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );
use somedb;
for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i});
db.helloDoc.countDocuments();
EOF
