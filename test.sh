#!/bin/bash

# Función para mostrar el uso del script
show_usage() {
    echo "Uso: $0 <URL> <directorio_destino>"
    echo "Ejemplo: $0 https://ejemplo.com/galeria imagenes"
}

# Verificar si se proporcionaron los argumentos necesarios
if [ $# -ne 2 ]; then
    show_usage
    exit 1
fi

# Asignar argumentos a variables
url="$1"
output_dir="$2"

# Extraer el dominio base de la URL
base_url=$(echo "$url" | sed -E 's|^(https?://[^/]+).*|\1|')

# Crear el directorio de salida si no existe
mkdir -p "$output_dir"

# Función para descargar usando curl o, si no está disponible, usando /dev/tcp
download() {
    if command -v curl &> /dev/null; then
        curl -s -L "$1" -o "$2"
    else
        exec 3<>/dev/tcp/${1#*//}/80
        echo -e "GET ${1#*://*/} HTTP/1.1\r\nHost: ${1#*://}\r\nConnection: close\r\n\r\n" >&3
        sed '1,/^\r$/d' <&3 > "$2"
        exec 3>&-
    fi
}

# Función para obtener la extensión correcta del archivo
get_extension() {
    local mime_type
    mime_type=$(file -b --mime-type "$1")
    case "$mime_type" in
        image/jpeg) echo "jpg" ;;
        image/png) echo "png" ;;
        image/gif) echo "gif" ;;
        image/webp) echo "webp" ;;
        *) echo "unknown" ;;
    esac
}

# Descargar la página web
echo "Descargando la página web..."
download "$url" temp.html

if [ ! -s temp.html ]; then
    echo "Error al descargar la página web. Verifica la URL y tu conexión a internet."
    exit 1
fi

# Extraer las URLs de las imágenes
echo "Extrayendo URLs de imágenes..."
grep -oE 'src="[^"]*\.(jpg|jpeg|png|gif|webp)"' temp.html | sed 's/src="//;s/"$//' > image_urls.txt

# Descargar las imágenes
echo "Descargando imágenes..."
while IFS= read -r img_url
do
    # Construir la URL completa de la imagen
    if [[ "$img_url" == /* ]]; then
        # URL absoluta desde la raíz del dominio
        full_img_url="${base_url}${img_url}"
    elif [[ "$img_url" != http* ]]; then
        # URL relativa
        full_img_url="${base_url}/${img_url#/}"
    else
        # URL completa
        full_img_url="$img_url"
    fi
    
    # Obtener el nombre base del archivo
    filename=$(basename "$full_img_url")
    
    # Descargar la imagen a un archivo temporal
    temp_file="${output_dir}/temp_${filename}"
    download "$full_img_url" "$temp_file"
    
    if [ -s "$temp_file" ]; then
        # Obtener la extensión correcta
        extension=$(get_extension "$temp_file")
        
        if [ "$extension" != "unknown" ]; then
            # Renombrar el archivo con la extensión correcta
            mv "$temp_file" "${output_dir}/${filename%.*}.${extension}"
            echo "Descargada: $full_img_url como ${filename%.*}.${extension}"
        else
            echo "Error: No se pudo determinar el formato de $full_img_url"
            rm "$temp_file"
        fi
    else
        echo "Error al descargar: $full_img_url"
        rm -f "$temp_file"
    fi
done < image_urls.txt

# Limpiar archivos temporales
rm temp.html image_urls.txt

echo "Descarga completada. Las imágenes se han guardado en: $output_dir"