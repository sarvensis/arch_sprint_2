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

wait_for_service "configSrv" 27018
echo "Инициализация Config Server Replica Set..."
docker-compose exec -T configSrv mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
    _id : "config_server",
    configsvr: true,
    members: [
        { _id : 0, host : "configSrv:27018" }
    ]
})
EOF
echo "Инициализация Config Server Replica Set..."


wait_for_service "shard1-primary" 27019
wait_for_service "shard1-secondary1" 27020
wait_for_service "shard1-secondary2" 27021
echo "Инициализация Shard1 Replica Set..."
docker-compose exec -T shard1-primary mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
    _id: "shard1ReplSet",
    members: [
        { _id: 0, host: "shard1-primary:27019" },
        { _id: 1, host: "shard1-secondary1:27020" },
        { _id: 2, host: "shard1-secondary2:27021" }
    ]
});
EOF

wait_for_service "shard2-primary" 27022
wait_for_service "shard2-secondary1" 27023
wait_for_service "shard2-secondary2" 27024
echo "Инициализация Shard2 Replica Set..."
docker-compose exec -T shard2-primary mongosh --port 27022 --quiet <<'EOF'
rs.initiate({
    _id: "shard2ReplSet",
    members: [
        { _id: 0, host: "shard2-primary:27022" },
        { _id: 1, host: "shard2-secondary1:27023" },
        { _id: 2, host: "shard2-secondary2:27024" }
    ]
});
EOF

wait_for_service "mongos_router" 27017
echo "Инициализация Роутера..."
docker-compose exec -T mongos_router mongosh --port 27017 --quiet <<'EOF'
sh.addShard( "shard1ReplSet/shard1-primary:27019");
sh.addShard( "shard2ReplSet/shard2-primary:27022");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );
use somedb;
for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i});
db.helloDoc.countDocuments();
EOF
