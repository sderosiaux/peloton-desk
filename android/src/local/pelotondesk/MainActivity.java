package local.pelotondesk;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceError;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.webkit.JsResult;
import android.net.Uri;

public class MainActivity extends Activity {
    private WebView web;
    private BikeSensors sensors;
    private final Handler handler = new Handler();
    private static final String URL = "http://127.0.0.1:8765/";
    private final Runnable retry = () -> web.loadUrl(URL);

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        saveToken(getIntent());
        sensors = new BikeSensors(this);
        web = new WebView(this);
        web.setBackgroundColor(0xfff5f4ef);
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false);
        web.getSettings().setAllowContentAccess(false);
        web.addJavascriptInterface(new Bridge(), "DeskDevice");
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri uri = req.getUrl();
                return !("http".equals(uri.getScheme()) && "127.0.0.1".equals(uri.getHost()) && uri.getPort() == 8765);
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError error) {
                if (!req.isForMainFrame()) return;
                handler.removeCallbacks(retry);
                view.loadDataWithBaseURL(URL, "<body style='background:#f5f4ef;color:#242e29;font:24px sans-serif;padding:70px'><h1>Peloton Desk</h1><p>Ouvrez Peloton Desk Mac sur votre ordinateur.</p><p style='font-size:16px;color:#758077'>La connexion reprendra automatiquement.</p></body>", "text/html", "UTF-8", null);
                handler.postDelayed(retry, 3000);
            }
        });
        setContentView(web);
        sensors.start();
        web.loadUrl(URL);
    }
    private void saveToken(Intent intent) {
        String token = intent.getStringExtra("token");
        if (token != null && token.matches("[A-Za-z0-9_-]{30,100}"))
            getPreferences(MODE_PRIVATE).edit().putString("token", token).apply();
    }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); setIntent(intent); saveToken(intent); web.loadUrl(URL); }
    @Override protected void onPause() { super.onPause(); web.evaluateJavascript("window.DeskPause&&window.DeskPause()", null); }
    @Override protected void onDestroy() { handler.removeCallbacks(retry); sensors.stop(); web.destroy(); super.onDestroy(); }
    private class Bridge {
        @JavascriptInterface public String connectionToken() { return getPreferences(MODE_PRIVATE).getString("token", ""); }
        @JavascriptInterface public String metrics() { return sensors.json(); }
    }
}
