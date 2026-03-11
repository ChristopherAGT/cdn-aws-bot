import os
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, filters, ContextTypes
import boto3
import subprocess

# Diccionario para guardar credenciales temporalmente
user_sessions = {}

# -------------------- Comandos básicos --------------------
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "📡 Bienvenido usuario, este Bot de CloudFront\n"
        "Para empezar, ingresa tus credenciales de AWS con /aws\n"
        "Comandos disponibles:\n"
        "/listar - listar distribuciones\n"
        "/uso - ver uso de transferencia\n"
        "/crear - crear distribución\n"
        "/eliminar - eliminar distribución\n"
        "/estado - ver estado del VPS"
    )

# -------------------- Configuración AWS por usuario --------------------
async def aws(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.message.from_user.id
    user_sessions[user_id] = {"state": "asking_access_key"}
    await update.message.reply_text("Ingresa tu AWS Access Key ID:")

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.message.from_user.id
    text = update.message.text.strip()

    if user_id not in user_sessions:
        await update.message.reply_text("Por favor inicia con /aws primero")
        return

    session = user_sessions[user_id]

    if session.get("state") == "asking_access_key":
        session["aws_key"] = text
        session["state"] = "asking_secret_key"
        await update.message.reply_text("Ahora ingresa tu AWS Secret Access Key:")
    elif session.get("state") == "asking_secret_key":
        session["aws_secret"] = text
        session["state"] = "asking_region"
        await update.message.reply_text("Finalmente, ingresa la región de AWS (ej. us-east-1):")
    elif session.get("state") == "asking_region":
        session["region"] = text
        session["state"] = "ready"
        await update.message.reply_text("✅ ¡Credenciales guardadas temporalmente! Ahora puedes usar los comandos del bot.")

# -------------------- Función para crear sesión boto3 por usuario --------------------
def get_aws_session(user_id):
    session = user_sessions.get(user_id)
    if not session or session.get("state") != "ready":
        return None
    return boto3.Session(
        aws_access_key_id=session["aws_key"],
        aws_secret_access_key=session["aws_secret"],
        region_name=session["region"]
    )

# -------------------- Comandos del bot --------------------
async def listar(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.message.from_user.id
    aws_session = get_aws_session(user_id)
    if not aws_session:
        await update.message.reply_text("Primero ingresa tus credenciales con /aws")
        return
    cf = aws_session.client("cloudfront")
    dist_list = cf.list_distributions()
    ids = [item["Id"] for item in dist_list.get("DistributionList", {}).get("Items", [])]
    await update.message.reply_text(f"Distribuciones: {ids if ids else 'No hay distribuciones'}")

async def uso(update: Update, context: ContextTypes.DEFAULT_TYPE):
    # Aquí puedes llamar a tu script ver_uso.sh
    result = subprocess.getoutput("./scripts/ver_uso.sh")
    await update.message.reply_text(f"Uso de transferencia:\n{result}")

async def crear(update: Update, context: ContextTypes.DEFAULT_TYPE):
    result = subprocess.getoutput("./scripts/crear_cloudfront.sh")
    await update.message.reply_text(result)

async def eliminar(update: Update, context: ContextTypes.DEFAULT_TYPE):
    result = subprocess.getoutput("./scripts/eliminar_distribucion.sh")
    await update.message.reply_text(result)

async def estado(update: Update, context: ContextTypes.DEFAULT_TYPE):
    result = subprocess.getoutput("uptime")
    await update.message.reply_text(f"Estado VPS:\n{result}")

# -------------------- Inicializar bot --------------------
app = ApplicationBuilder().token(os.getenv("TELEGRAM_TOKEN")).build()
app.add_handler(CommandHandler("start", start))
app.add_handler(CommandHandler("aws", aws))
app.add_handler(CommandHandler("listar", listar))
app.add_handler(CommandHandler("uso", uso))
app.add_handler(CommandHandler("crear", crear))
app.add_handler(CommandHandler("eliminar", eliminar))
app.add_handler(CommandHandler("estado", estado))
app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
app.run_polling()
