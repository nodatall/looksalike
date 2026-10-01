export const PHOTO_RECIPE = Object.freeze({
  version: "jpeg-v1",
  maxSourceBytes: 10 * 1024 * 1024,
  maxPixels: 20_000_000,
  maxOutputBytes: 450_000,
  maxEdge: 1600,
  resizeFactor: 0.75,
  resizePasses: 6,
  qualities: Object.freeze([0.86, 0.76, 0.66, 0.56, 0.46]),
  background: "#ffffff",
});

const MESSAGES = {
  unsupported: "Choose a JPEG, PNG, or WebP photo.",
  too_large: "Choose a photo no larger than 10 MB.",
  dimensions: "Choose a photo no larger than 20 megapixels.",
  animated: "Choose a still photo instead of an animation.",
  malformed: "This photo could not be read. Choose another photo.",
  compression: "This photo could not be made small enough. Choose another photo.",
};

export class PhotoError extends Error {
  constructor(code) {
    super(MESSAGES[code]);
    this.name = "PhotoError";
    this.code = code;
  }
}

// Header inspection precedes image decoding and canvas allocation.
export function inspectPhoto(bytes, declaredType = "") {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const text = (offset, count) => String.fromCharCode(...bytes.subarray(offset, offset + count));
  let type;
  let width;
  let height;
  try {
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
      type = "image/jpeg";
      let offset = 2;
      while (offset + 4 <= bytes.length) {
        if (bytes[offset++] !== 0xff) throw new PhotoError("malformed");
        while (bytes[offset] === 0xff) offset++;
        const marker = bytes[offset++];
        if (marker === 0xda || marker === 0xd9) break;
        const length = view.getUint16(offset);
        if (length < 2 || offset + length > bytes.length) throw new PhotoError("malformed");
        if (
          [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(
            marker,
          )
        ) {
          height = view.getUint16(offset + 3);
          width = view.getUint16(offset + 5);
          break;
        }
        offset += length;
      }
    } else if (text(0, 8) === "\x89PNG\r\n\x1a\n") {
      type = "image/png";
      if (text(12, 4) !== "IHDR" || view.getUint32(8) !== 13) throw new PhotoError("malformed");
      width = view.getUint32(16);
      height = view.getUint32(20);
      for (let offset = 8; offset + 12 <= bytes.length; ) {
        const length = view.getUint32(offset);
        if (text(offset + 4, 4) === "acTL") throw new PhotoError("animated");
        offset += length + 12;
        if (offset > bytes.length) throw new PhotoError("malformed");
      }
    } else if (text(0, 4) === "RIFF" && text(8, 4) === "WEBP") {
      type = "image/webp";
      if (view.getUint32(4, true) + 8 !== bytes.length) throw new PhotoError("malformed");
      for (let offset = 12; offset + 8 <= bytes.length; ) {
        const kind = text(offset, 4);
        const length = view.getUint32(offset + 4, true);
        const start = offset + 8;
        if (start + length > bytes.length) throw new PhotoError("malformed");
        if (kind === "ANIM" || kind === "ANMF" || (kind === "VP8X" && bytes[start] & 2))
          throw new PhotoError("animated");
        if (kind === "VP8X") {
          width = 1 + bytes[start + 4] + (bytes[start + 5] << 8) + (bytes[start + 6] << 16);
          height = 1 + bytes[start + 7] + (bytes[start + 8] << 8) + (bytes[start + 9] << 16);
        } else if (kind === "VP8 " && width === undefined) {
          if (text(start + 3, 3) !== "\x9d\x01\x2a") throw new PhotoError("malformed");
          width = view.getUint16(start + 6, true) & 0x3fff;
          height = view.getUint16(start + 8, true) & 0x3fff;
        } else if (kind === "VP8L" && width === undefined) {
          if (bytes[start] !== 0x2f) throw new PhotoError("malformed");
          const bits = view.getUint32(start + 1, true);
          width = (bits & 0x3fff) + 1;
          height = ((bits >>> 14) & 0x3fff) + 1;
        }
        offset = start + length + (length % 2);
      }
    } else {
      throw new PhotoError("unsupported");
    }
    if (declaredType && declaredType !== type) throw new PhotoError("unsupported");
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0)
      throw new PhotoError("malformed");
    if (width * height > PHOTO_RECIPE.maxPixels) throw new PhotoError("dimensions");
    return { type, width, height };
  } catch (error) {
    if (error instanceof PhotoError) throw error;
    throw new PhotoError("malformed");
  }
}

export async function preparePhoto(file, { signal } = {}) {
  signal?.throwIfAborted();
  if (!file || file.size === 0) throw new PhotoError("malformed");
  if (file.size > PHOTO_RECIPE.maxSourceBytes) throw new PhotoError("too_large");
  const bytes = new Uint8Array(await file.arrayBuffer());
  const source = inspectPhoto(bytes, file.type);
  signal?.throwIfAborted();
  let bitmap;
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
    signal?.throwIfAborted();
    if (bitmap.width * bitmap.height > PHOTO_RECIPE.maxPixels) throw new PhotoError("dimensions");
    const canvas = document.createElement("canvas");
    const context = canvas.getContext("2d", { alpha: false });
    if (!context) throw new PhotoError("compression");
    const scale = Math.min(1, PHOTO_RECIPE.maxEdge / Math.max(bitmap.width, bitmap.height));
    for (let pass = 0; pass < PHOTO_RECIPE.resizePasses; pass++) {
      const passScale = scale * PHOTO_RECIPE.resizeFactor ** pass;
      canvas.width = Math.max(1, Math.round(bitmap.width * passScale));
      canvas.height = Math.max(1, Math.round(bitmap.height * passScale));
      context.fillStyle = PHOTO_RECIPE.background;
      context.fillRect(0, 0, canvas.width, canvas.height);
      context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      for (const quality of PHOTO_RECIPE.qualities) {
        signal?.throwIfAborted();
        const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));
        signal?.throwIfAborted();
        if (
          blob?.type === "image/jpeg" &&
          blob.size > 0 &&
          blob.size <= PHOTO_RECIPE.maxOutputBytes
        ) {
          return {
            blob,
            width: canvas.width,
            height: canvas.height,
            quality,
            recipe: PHOTO_RECIPE.version,
            source,
          };
        }
      }
    }
    throw new PhotoError("compression");
  } catch (error) {
    if (signal?.aborted) throw signal.reason;
    if (error instanceof PhotoError) throw error;
    throw new PhotoError("malformed");
  } finally {
    bitmap?.close();
  }
}
