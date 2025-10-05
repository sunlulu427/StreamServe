<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" omit-xml-declaration="yes" indent="yes"/>

  <xsl:template match="/">
    <html>
      <head>
        <title>StreamServe RTMP 状态</title>
        <meta charset="utf-8"/>
        <style>
          body { font-family: sans-serif; margin: 2rem; }
          h1 { font-size: 1.6rem; }
          table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
          th, td { border: 1px solid #ccc; padding: 0.5rem; text-align: left; }
          th { background: #f5f5f5; }
        </style>
      </head>
      <body>
        <h1>RTMP 应用状态</h1>
        <xsl:for-each select="rtmp/server/application">
          <h2>
            <xsl:value-of select="name"/>
          </h2>
          <table>
            <thead>
              <tr>
                <th>流名称</th>
                <th>发布者</th>
                <th>订阅者数量</th>
                <th>比特率 (kbps)</th>
              </tr>
            </thead>
            <tbody>
              <xsl:choose>
                <xsl:when test="live/publisher">
                  <xsl:for-each select="live/publisher">
                    <tr>
                      <td><xsl:value-of select="../name"/></td>
                      <td><xsl:value-of select="client"/></td>
                      <td><xsl:value-of select="nclients"/></td>
                      <td><xsl:value-of select="bw_in"/></td>
                    </tr>
                  </xsl:for-each>
                </xsl:when>
                <xsl:otherwise>
                  <tr>
                    <td colspan="4">当前无推流任务</td>
                  </tr>
                </xsl:otherwise>
              </xsl:choose>
            </tbody>
          </table>
        </xsl:for-each>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
