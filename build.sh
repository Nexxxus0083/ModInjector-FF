#!/bin/bash

# Script de build automatizado para Memory Injector
# Uso: ./build.sh [clean|compile|sign|package|all]

set -e  # Parar em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
PROJECT_NAME="MemoryInjector"
BUNDLE_ID="com.memoryinjector.app"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$PROJECT_NAME.app"
PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_FILE="$BUILD_DIR/$PROJECT_NAME.ipa"

# Funções de log
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Verificar dependências
check_dependencies() {
    log_info "Verificando dependências..."
    
    if ! command -v swiftc &> /dev/null; then
        log_error "Swift compiler não encontrado!"
        log_info "Instale o Xcode e Command Line Tools"
        exit 1
    fi
    
    if ! command -v xcrun &> /dev/null; then
        log_error "xcrun não encontrado!"
        log_info "Instale o Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi
    
    if ! command -v ldid &> /dev/null; then
        log_warning "ldid não encontrado!"
        log_info "Instale com: brew install ldid"
        log_info "Ou baixe de: https://github.com/ProcursusTeam/ldid"
        log_info "Continuando sem assinatura..."
        SKIP_SIGNING=1
    fi
    
    log_success "Dependências verificadas"
}

# Limpar build anterior
clean_build() {
    log_info "Limpando build anterior..."
    rm -rf "$BUILD_DIR"
    log_success "Limpeza concluída"
}

# Compilar projeto
compile_project() {
    log_info "Compilando $PROJECT_NAME..."
    
    # Criar diretórios
    mkdir -p "$APP_DIR"
    
    # Obter SDK path
    SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
    log_info "SDK: $SDK_PATH"
    
    # Coletar arquivos fonte
    SOURCES=$(find App Core Bridge UI Utils -name "*.swift" 2>/dev/null | tr '\n' ' ')
    
    if [ -z "$SOURCES" ]; then
        log_error "Nenhum arquivo Swift encontrado!"
        exit 1
    fi
    
    log_info "Arquivos encontrados: $(echo $SOURCES | wc -w)"
    
    # Compilar
    xcrun swiftc \
        -target arm64-apple-ios14.0 \
        -sdk "$SDK_PATH" \
        -O \
        -whole-module-optimization \
        -framework UIKit \
        -framework Foundation \
        -framework WebKit \
        -framework CoreGraphics \
        -emit-executable \
        -o "$APP_DIR/$PROJECT_NAME" \
        $SOURCES
    
    if [ $? -eq 0 ]; then
        log_success "Compilação concluída"
    else
        log_error "Falha na compilação"
        exit 1
    fi
    
    # Copiar recursos
    log_info "Copiando recursos..."
    
    if [ -f "App/Info.plist" ]; then
        cp "App/Info.plist" "$APP_DIR/"
        log_success "Info.plist copiado"
    else
        log_error "Info.plist não encontrado!"
        exit 1
    fi
    
    if [ -d "UI/Assets" ]; then
        cp -r "UI/Assets" "$APP_DIR/"
        log_success "Assets copiados"
    else
        log_warning "Pasta Assets não encontrada"
    fi
    
    # Tornar executável
    chmod +x "$APP_DIR/$PROJECT_NAME"
    
    # Mostrar tamanho
    SIZE=$(du -h "$APP_DIR/$PROJECT_NAME" | cut -f1)
    log_info "Tamanho do executável: $SIZE"
    
    log_success "Build concluído"
}

# Assinar aplicativo
sign_app() {
    if [ -n "$SKIP_SIGNING" ]; then
        log_warning "Pulando assinatura (ldid não disponível)"
        return
    fi
    
    log_info "Assinando aplicativo..."
    
    if [ ! -f "$PROJECT_NAME.entitlements" ]; then
        log_error "Arquivo de entitlements não encontrado!"
        exit 1
    fi
    
    ldid -S"$PROJECT_NAME.entitlements" "$APP_DIR/$PROJECT_NAME"
    
    if [ $? -eq 0 ]; then
        log_success "Assinatura aplicada"
        
        # Verificar entitlements
        log_info "Verificando entitlements..."
        ldid -e "$APP_DIR/$PROJECT_NAME" | head -5
    else
        log_error "Falha na assinatura"
        exit 1
    fi
}

# Criar IPA
package_ipa() {
    log_info "Criando IPA..."
    
    # Criar estrutura Payload
    mkdir -p "$PAYLOAD_DIR"
    cp -r "$APP_DIR" "$PAYLOAD_DIR/"
    
    # Comprimir
    cd "$BUILD_DIR"
    zip -qr "$PROJECT_NAME.ipa" Payload
    cd ..
    
    # Limpar Payload temporário
    rm -rf "$PAYLOAD_DIR"
    
    if [ -f "$IPA_FILE" ]; then
        SIZE=$(du -h "$IPA_FILE" | cut -f1)
        log_success "IPA criado: $IPA_FILE ($SIZE)"
    else
        log_error "Falha ao criar IPA"
        exit 1
    fi
}

# Verificar IPA
verify_ipa() {
    log_info "Verificando IPA..."
    
    if [ ! -f "$IPA_FILE" ]; then
        log_error "IPA não encontrado!"
        return 1
    fi
    
    # Descompactar temporariamente
    TEMP_DIR=$(mktemp -d)
    unzip -q "$IPA_FILE" -d "$TEMP_DIR"
    
    # Verificar estrutura
    if [ -d "$TEMP_DIR/Payload/$PROJECT_NAME.app" ]; then
        log_success "Estrutura do IPA válida"
        
        # Verificar executável
        if [ -f "$TEMP_DIR/Payload/$PROJECT_NAME.app/$PROJECT_NAME" ]; then
            log_success "Executável presente"
        else
            log_error "Executável não encontrado no IPA"
        fi
        
        # Verificar Info.plist
        if [ -f "$TEMP_DIR/Payload/$PROJECT_NAME.app/Info.plist" ]; then
            log_success "Info.plist presente"
        else
            log_error "Info.plist não encontrado no IPA"
        fi
    else
        log_error "Estrutura do IPA inválida"
    fi
    
    # Limpar
    rm -rf "$TEMP_DIR"
}

# Instalar no dispositivo
install_device() {
    log_info "Instalando no dispositivo..."
    
    if ! command -v ideviceinstaller &> /dev/null; then
        log_warning "ideviceinstaller não encontrado"
        log_info "Instale manualmente o IPA via TrollStore"
        log_info "Ou instale ideviceinstaller: brew install ideviceinstaller"
        return
    fi
    
    # Verificar dispositivo conectado
    if ! idevice_id -l &> /dev/null; then
        log_error "Nenhum dispositivo iOS conectado"
        return 1
    fi
    
    DEVICE_ID=$(idevice_id -l | head -1)
    log_info "Dispositivo encontrado: $DEVICE_ID"
    
    # Instalar
    ideviceinstaller -i "$IPA_FILE"
    
    if [ $? -eq 0 ]; then
        log_success "Instalação concluída"
    else
        log_error "Falha na instalação"
    fi
}

# Mostrar ajuda
show_help() {
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos:"
    echo "  clean      - Limpar build anterior"
    echo "  compile    - Compilar código fonte"
    echo "  sign       - Assinar aplicativo"
    echo "  package    - Criar IPA"
    echo "  verify     - Verificar IPA"
    echo "  install    - Instalar no dispositivo"
    echo "  all        - Executar tudo (padrão)"
    echo "  help       - Mostrar esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  $0              # Build completo"
    echo "  $0 all          # Build completo"
    echo "  $0 clean        # Apenas limpar"
    echo "  $0 compile      # Apenas compilar"
}

# Função principal
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   Memory Injector Build Script         ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # Verificar se estamos no diretório correto
    if [ ! -f "Makefile" ] || [ ! -d "App" ]; then
        log_error "Execute este script no diretório raiz do projeto!"
        exit 1
    fi
    
    # Processar comando
    COMMAND=${1:-all}
    
    case $COMMAND in
        clean)
            check_dependencies
            clean_build
            ;;
        compile)
            check_dependencies
            compile_project
            ;;
        sign)
            check_dependencies
            sign_app
            ;;
        package)
            package_ipa
            ;;
        verify)
            verify_ipa
            ;;
        install)
            install_device
            ;;
        all)
            check_dependencies
            clean_build
            compile_project
            sign_app
            package_ipa
            verify_ipa
            echo ""
            log_success "Build completo concluído!"
            log_info "IPA localizado em: $IPA_FILE"
            echo ""
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Comando desconhecido: $COMMAND"
            show_help
            exit 1
            ;;
    esac
    
    echo ""
}

# Executar
main "$@"
