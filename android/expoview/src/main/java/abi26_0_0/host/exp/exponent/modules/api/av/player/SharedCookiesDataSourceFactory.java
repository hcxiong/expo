package abi26_0_0.host.exp.exponent.modules.api.av.player;

import android.content.Context;
import android.net.Uri;

import com.google.android.exoplayer2.upstream.DataSource;
import com.google.android.exoplayer2.upstream.DefaultDataSourceFactory;
import com.google.android.exoplayer2.upstream.DefaultHttpDataSourceFactory;
import com.google.android.exoplayer2.upstream.HttpDataSource;

import java.net.URI;
import java.util.List;

import expolib_v1.okhttp3.Cookie;
import expolib_v1.okhttp3.HttpUrl;
import host.exp.exponent.ReactNativeStaticHelpers;

public class SharedCookiesDataSourceFactory implements DataSource.Factory {
  private final Uri mUri;
  private final DataSource.Factory mDataSourceFactory;
  public SharedCookiesDataSourceFactory(Uri uri, Context context, String userAgent) {
    if (uri.getScheme().equals("http") || uri.getScheme().equals("https")) {
      mDataSourceFactory = new DefaultHttpDataSourceFactory(userAgent);
    } else {
      mDataSourceFactory = new DefaultDataSourceFactory(context, userAgent);
    }
    mUri = uri;
  }

  @Override
  public DataSource createDataSource() {
    DataSource dataSource = mDataSourceFactory.createDataSource();
    if (dataSource instanceof HttpDataSource) {
      setDataSourceCookies((HttpDataSource) dataSource, mUri);
    }
    return dataSource;
  }

  private void setDataSourceCookies(HttpDataSource dataSource, Uri uri) {
    HttpUrl url = HttpUrl.get(URI.create(uri.toString()));
    List<Cookie> cookies = ReactNativeStaticHelpers.getOkHttpClient(this.getClass()).cookieJar().loadForRequest(url);
    StringBuilder cookieValue = new StringBuilder();
    for(Cookie cookie : cookies) {
      if (cookie.matches(url)) {
        cookieValue.append(cookieToString(cookie));
      }
    }
    dataSource.setRequestProperty("Cookie", cookieValue.toString());
  }

  private String cookieToString(Cookie cookie) {
    return cookie.name() + "=" + cookie.value() + "; ";
  }
}
