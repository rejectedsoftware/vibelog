module vibelog.rss;

import vibe.core.stream;
import vibe.inet.message : toRFC822DateTimeString;

import std.datetime;


final class RssFeed {
	RssChannel[] channels;

	void render(OutputStream dst)
	{
		dst.write("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
		dst.write("<rss version=\"2.0\">\n");
		foreach( ch; channels )
			ch.render(dst);
		dst.write("</rss>\n");
		dst.flush();
	}
}

final class RssChannel {
	string title;
	string link;
	string description;
	string language = "en-us";
	string copyright;
	SysTime pubDate;

	string imageTitle;
	string imageUrl;
	string imageLink;

	RssEntry[] entries;

	void render(OutputStream dst)
	{
		dst.write("\t<channel>\n");
		dst.write("\t\t<title>"); dst.write(title); dst.write("</title>\n");
		dst.write("\t\t<link>"); dst.write(link); dst.write("</link>\n");
		dst.write("\t\t<description>"); dst.write(description); dst.write("</description>\n");
		dst.write("\t\t<language>"); dst.write(language); dst.write("</language>\n");
		dst.write("\t\t<copyright>"); dst.write(copyright); dst.write("</copyright>\n");
		dst.write("\t\t<pubDate>"); dst.write(toRFC822DateTimeString(pubDate)); dst.write("</pubDate>\n");
		if( imageUrl.length ){
			dst.write("\t\t<image>\n");
			dst.write("\t\t\t<url>"); dst.write(imageUrl); dst.write("</url>\n");
			dst.write("\t\t\t<title>"); dst.write(imageTitle); dst.write("</title>\n");
			dst.write("\t\t\t<link>"); dst.write(imageLink); dst.write("</link>\n");
			dst.write("\t\t</image>\n");
		}
		foreach( e; entries )
			e.render(dst);
		dst.write("\t</channel>\n");
	}
}

final class RssEntry {
	string title;
	string description;
	string link;
	string language = "en-us";
	string author;
	string guid;
	SysTime pubDate;

	void render(OutputStream dst)
	{
		dst.write("\t\t<item>\n");
		dst.write("\t\t\t<title>"); dst.write(title); dst.write("</title>\n");
		dst.write("\t\t\t<description>"); dst.write(description); dst.write("</description>\n");
		dst.write("\t\t\t<link>"); dst.write(link); dst.write("</link>\n");
		dst.write("\t\t\t<author>"); dst.write(author); dst.write("</author>\n");
		dst.write("\t\t\t<guid>"); dst.write(guid); dst.write("</guid>\n");
		dst.write("\t\t\t<pubDate>"); dst.write(toRFC822DateTimeString(pubDate)); dst.write("</pubDate>\n");
		dst.write("\t\t</item>\n");
	}
}
