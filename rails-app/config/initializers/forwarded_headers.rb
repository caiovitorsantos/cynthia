# TM-26: o IP do cliente (remote_ip, chave do rate_limit do login) vem só do X-Forwarded-For que o Caddy
# reescreve. O cabeçalho Forwarded vem do cliente sem filtro e, lido primeiro pelo Rack, deixava trocar
# de "IP" a cada tentativa.
Rack::Request.forwarded_priority = [ :x_forwarded ]
