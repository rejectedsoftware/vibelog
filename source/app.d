import vibe.d;

import vibelog.vibelog;

static this()
{
	//setLogLevel(LogLevel.Trace);

	auto router = new UrlRouter;

	auto blogsettings = new VibeLogSettings;
	blogsettings.configName = "vibelog";
	blogsettings.siteUrl = Url.parse("http://localhost:8080/");
	registerVibeLog(blogsettings, router);
	
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	listenHttp(settings, router);
}
