package com.webapp.erimaxmanuteno;

import android.content.ContentValues;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.OutputStream;

@CapacitorPlugin(name = "EriMaxExport")
public class EriMaxExportPlugin extends Plugin {
    @PluginMethod
    public void saveFile(PluginCall call) {
        String filename = call.getString("filename");
        String mimeType = call.getString("mimeType");
        String base64 = call.getString("base64");
        if (filename == null || filename.trim().isEmpty() || mimeType == null || base64 == null) {
            call.reject("Dados do arquivo incompletos.");
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            call.reject("Salvar diretamente em Downloads requer Android 10 ou superior.");
            return;
        }
        Uri uri = null;
        try {
            byte[] bytes = Base64.decode(base64, Base64.DEFAULT);
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, filename);
            values.put(MediaStore.MediaColumns.MIME_TYPE, mimeType);
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/EriMax");
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);
            uri = getContext().getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) throw new IllegalStateException("O Android não criou o arquivo.");
            try (OutputStream output = getContext().getContentResolver().openOutputStream(uri)) {
                if (output == null) throw new IllegalStateException("Não foi possível gravar o arquivo.");
                output.write(bytes);
                output.flush();
            }
            ContentValues ready = new ContentValues();
            ready.put(MediaStore.MediaColumns.IS_PENDING, 0);
            getContext().getContentResolver().update(uri, ready, null, null);
            JSObject result = new JSObject();
            result.put("uri", uri.toString());
            call.resolve(result);
        } catch (Exception error) {
            if (uri != null) getContext().getContentResolver().delete(uri, null, null);
            call.reject("Falha ao salvar em Downloads/EriMax: " + error.getMessage(), error);
        }
    }
}
