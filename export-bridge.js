import { registerPlugin } from '@capacitor/core';
import { Printer } from '@capgo/capacitor-printer';

const EriMaxExport = registerPlugin('EriMaxExport');
const isNative = () => Boolean(window.Capacitor?.isNativePlatform?.());

window.erimaxNativeExports = {
  async saveExcel({ filename, base64 }) {
    if (!isNative()) throw new Error('A exportação nativa só está disponível no aplicativo Android.');
    return EriMaxExport.saveFile({
      filename,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      base64,
    });
  },
  async printHtml({ html, name }) {
    if (!isNative()) return window.print();
    return Printer.printHtml({ html, name });
  },
};
