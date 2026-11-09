import { FileSharer } from '@capgo/capacitor-file-sharer';
import { Printer } from '@capgo/capacitor-printer';

const isNative = () => Boolean(window.Capacitor?.isNativePlatform?.());

window.erimaxNativeExports = {
  async saveExcel({ filename, base64 }) {
    if (!isNative()) throw new Error('A exportação nativa só está disponível no aplicativo Android.');
    return FileSharer.save({
      filename,
      contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      base64Data: base64,
      android: { saveDirectory: 'downloads', relativePath: 'Download/EriMax' },
    });
  },
  async printHtml({ html, name }) {
    if (!isNative()) return window.print();
    return Printer.printHtml({ html, name });
  },
};
