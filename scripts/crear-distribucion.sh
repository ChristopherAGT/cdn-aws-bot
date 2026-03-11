#!/bin/bash

# ╔════════════════════════════════════════════════════════════╗
# ║        🌐 CREAR DISTRIBUCIÓN CLOUDFRONT PARA BOT           ║
# ╚════════════════════════════════════════════════════════════╝

# Colores para salida
RED='\e[1;91m'
GREEN='\e[1;92m'
YELLOW='\e[1;93m'
CYAN='\e[1;96m'
BOLD='\e[1m'
RESET='\e[0m'

# --------------------
# Parámetros desde el bot
# $1 = ORIGIN_DOMAIN
# $2 = CNAME_DOMAIN (opcional)
# $3 = DESCRIPTION (opcional)
ORIGIN_DOMAIN=$1
CNAME_DOMAIN=$2
DESCRIPTION="${3:-Cloudfront_Bot}"

if [[ -z "$ORIGIN_DOMAIN" ]]; then
    echo -e "${RED}❌ ORIGIN_DOMAIN no proporcionado.${RESET}"
    exit 1
fi

USE_CNAME=false
if [[ -n "$CNAME_DOMAIN" ]]; then
    USE_CNAME=true
fi

# --------------------
# Comprobar dependencias
check_command() {
    local cmd="$1"
    local pkg="$2"
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}⚙️ Instalando ${pkg}...${RESET}"
        apt-get update -qq
        apt-get install -y "$pkg"
    fi
}

check_command aws awscli
check_command jq jq

# --------------------
# Configuración de referencia
REFERENCE="cf-bot-$(date +%s)"

# Buscar certificado SSL si hay CNAME
if [ "$USE_CNAME" = true ]; then
    ROOT_DOMAIN=$(echo "$CNAME_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
    CERT_ARN=$(aws acm list-certificates --region us-east-1 --output json | \
        jq -r --arg domain "$ROOT_DOMAIN" '.CertificateSummaryList[] | select(.DomainName | test($domain+"$")) | .CertificateArn' | head -n 1)
    if [[ -z "$CERT_ARN" ]]; then
        echo -e "${RED}❌ No se encontró certificado SSL para ${ROOT_DOMAIN}.${RESET}"
        exit 1
    fi
fi

# --------------------
# Generar config_cloudfront.json
if [ "$USE_CNAME" = true ]; then
cat > config_cloudfront.json <<EOF
{
  "CallerReference": "${REFERENCE}",
  "Comment": "${DESCRIPTION}",
  "Enabled": true,
  "PriceClass": "PriceClass_100",
  "HttpVersion": "http1.1",
  "IsIPV6Enabled": true,
  "Aliases": {
    "Quantity": 1,
    "Items": ["${CNAME_DOMAIN}"]
  },
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "CustomOrigin",
        "DomainName": "${ORIGIN_DOMAIN}",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "match-viewer",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          }
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "CustomOrigin",
    "ViewerProtocolPolicy": "allow-all",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET","HEAD"]
      }
    },
    "Compress": false,
    "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
    "OriginRequestPolicyId": "216adef6-5c7f-47e4-b989-5492eafa07d3"
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "${CERT_ARN}",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  }
}
EOF
else
cat > config_cloudfront.json <<EOF
{
  "CallerReference": "${REFERENCE}",
  "Comment": "${DESCRIPTION}",
  "Enabled": true,
  "PriceClass": "PriceClass_100",
  "HttpVersion": "http1.1",
  "IsIPV6Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "CustomOrigin",
        "DomainName": "${ORIGIN_DOMAIN}",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "match-viewer",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          }
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "CustomOrigin",
    "ViewerProtocolPolicy": "allow-all",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET","HEAD"]
      }
    },
    "Compress": false,
    "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
    "OriginRequestPolicyId": "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }
}
EOF
fi

# --------------------
# Crear distribución CloudFront
if aws cloudfront create-distribution --distribution-config file://config_cloudfront.json > salida_cloudfront.json 2>error.log; then
    DOMAIN=$(jq -r '.Distribution.DomainName' salida_cloudfront.json)
    echo -e "${GREEN}🎉 Distribución creada: https://${DOMAIN}${RESET}"
else
    echo -e "${RED}💥 Error al crear distribución.${RESET}"
    cat error.log
    rm -f config_cloudfront.json salida_cloudfront.json error.log
    exit 1
fi

# --------------------
# Limpiar archivos temporales
rm -f config_cloudfront.json salida_cloudfront.json error.log

# --------------------
# Output final para bot
echo "ORIGIN_DOMAIN=${ORIGIN_DOMAIN}"
if [ "$USE_CNAME" = true ]; then
    echo "CNAME_DOMAIN=${CNAME_DOMAIN}"
    echo "CERT_ARN=${CERT_ARN}"
fi
echo "CLOUDFRONT_URL=https://${DOMAIN}"
