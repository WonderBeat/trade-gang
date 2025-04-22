#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["ipython", "websockets", "loguru"]
# ///
import http.server
import socketserver

FIRST_RESPONSE = """
{"code":"000000","message":null,"messageDetail":null,"data":{"catalogs":[{"catalogId":161,"parentCatalogId":null,"icon":"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png","catalogName":"Delisting","description":null,"catalogType":1,"total":777777,"articles":[{"id":208595,"code":"84d4dc37762944828f3e91c4eabb6bb6","title":"Notice of Removal of Spot Trading Pairs - 2024-08-23","type":1,"releaseDate":1724223602529},{"id":207854,"code":"f881d01a7e5f42cf9432b733ca355513","title":"Notice of Removal of Spot Trading Pairs - 2024-08-16","type":1,"releaseDate":1723611608432},{"id":207839,"code":"865c4e7e31b34b9bb439044d97414273","title":"Notice of Removal of Margin Trading Pairs - 2024-08-22","type":1,"releaseDate":1723608007883},{"id":207063,"code":"e2fcd2c945654c8d832395335429403e","title":"Binance Will Delist CVP, EPX, FOR, LOOM, REEF, VGX on 2024-08-26","type":1,"releaseDate":1723446011329},{"id":206836,"code":"e633a048a38a44c29828a441e4c4dac2","title":"Notice of Removal of Spot Trading Pairs - 2024-08-02","type":1,"releaseDate":1722409208662}],"catalogs":[]}]},"success":true}
    """
DELISTING = """
{"code":"000000","message":null,"messageDetail":null,"data":{"catalogs":[{"catalogId":161,"parentCatalogId":null,"icon":"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png","catalogName":"Delisting","description":null,"catalogType":1,"total":777777,"articles":[{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Binance Will Delist AERGO, AST, BURGER, COMBO, LINA on 2025-03-28","type":1,"releaseDate":1742536227777},{"id":230884,"code":"77c21bfbaec349c18709d6c49a49e03b","title":"Notice of Removal of Spot Trading Pairs - 2025-03-28 & 2025-03-31","type":1,"releaseDate":1742972401256},{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Binance Will Delist AERGO, AST, BURGER, COMBO, LINA on 2025-03-28","type":1,"releaseDate":1742536220352},{"id":229830,"code":"69ff9abd38ad4cfcbe4521f654278a7d","title":"Notice of Removal of Spot Trading Pairs - 2025-03-21","type":1,"releaseDate":1742356810621},{"id":229618,"code":"edf76712d2ea48f8916a32cfe1b82fb9","title":"Notice of Removal of Margin Trading Pairs - 2025-03-25","type":1,"releaseDate":1742266815394},{"id":228973,"code":"4b88b1f8848444d9ad7af3d406bff72e","title":"Notice of Removal of Spot Trading Pairs - 2025-03-14","type":1,"releaseDate":1741770011825},{"id":228025,"code":"820e86ea4d5145a1bc357682394552ba","title":"Notice of Removal of Spot Trading Pairs - 2025-03-07","type":1,"releaseDate":1741140001767},{"id":227872,"code":"487e8345ab8146bba30ce251e2f9f974","title":"Notice of Removal of Margin Trading Pairs - 2025-03-11","type":1,"releaseDate":1741060808105},{"id":227184,"code":"7600776423b74af5a8716354b0cdef8b","title":"Notice of Removal of Spot Trading Pairs - 2025-02-28","type":1,"releaseDate":1740546019347},{"id":226679,"code":"0d93139d71c64f74bd63749c141842fb","title":"Binance Earn: Notice on Removal of Dual Investment Token Pairs - 2025-02-21","type":1,"releaseDate":1740027606855},{"id":226537,"code":"d3f0e61ac6d942c98ede2cfeade10314","title":"Notice of Removal of Spot Trading Pairs - 2025-02-21","type":1,"releaseDate":1739937608036}],"catalogs":[]}]},"success":true}
    """

# # no important markers
NO_MARKERS_IN_TEXT = """
{"code":"000000","message":null,"messageDetail":null,"data":{"catalogs":[{"catalogId":161,"parentCatalogId":null,"icon":"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png","catalogName":"Delisting","description":null,"catalogType":1,"total":777777,"articles":[{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Someone will send me AERGO, AST, BURGER, COMBO, LINA tomorrow","type":1,"releaseDate":1742536227777},{"id":230884,"code":"77c21bfbaec349c18709d6c49a49e03b","title":"Notice of Removal of Spot Trading Pairs - 2025-03-28 & 2025-03-31","type":1,"releaseDate":1742972401256},{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Binance Will Delist AERGO, AST, BURGER, COMBO, LINA on 2025-03-28","type":1,"releaseDate":1742536220352},{"id":229830,"code":"69ff9abd38ad4cfcbe4521f654278a7d","title":"Notice of Removal of Spot Trading Pairs - 2025-03-21","type":1,"releaseDate":1742356810621},{"id":229618,"code":"edf76712d2ea48f8916a32cfe1b82fb9","title":"Notice of Removal of Margin Trading Pairs - 2025-03-25","type":1,"releaseDate":1742266815394},{"id":228973,"code":"4b88b1f8848444d9ad7af3d406bff72e","title":"Notice of Removal of Spot Trading Pairs - 2025-03-14","type":1,"releaseDate":1741770011825},{"id":228025,"code":"820e86ea4d5145a1bc357682394552ba","title":"Notice of Removal of Spot Trading Pairs - 2025-03-07","type":1,"releaseDate":1741140001767},{"id":227872,"code":"487e8345ab8146bba30ce251e2f9f974","title":"Notice of Removal of Margin Trading Pairs - 2025-03-11","type":1,"releaseDate":1741060808105},{"id":227184,"code":"7600776423b74af5a8716354b0cdef8b","title":"Notice of Removal of Spot Trading Pairs - 2025-02-28","type":1,"releaseDate":1740546019347},{"id":226679,"code":"0d93139d71c64f74bd63749c141842fb","title":"Binance Earn: Notice on Removal of Dual Investment Token Pairs - 2025-02-21","type":1,"releaseDate":1740027606855},{"id":226537,"code":"d3f0e61ac6d942c98ede2cfeade10314","title":"Notice of Removal of Spot Trading Pairs - 2025-02-21","type":1,"releaseDate":1739937608036}],"catalogs":[]}]},"success":true}
    """
# no coins
NO_COINS_IN_ANNOUNCE = """
{"code":"000000","message":null,"messageDetail":null,"data":{"catalogs":[{"catalogId":161,"parentCatalogId":null,"icon":"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png","catalogName":"Delisting","description":null,"catalogType":1,"total":777777,"articles":[{"id":230884,"code":"77c21bfbaec349c18709d6c49a49e03b","title":"Notice of Removal of Spot Trading Pairs - 2025-03-28 & 2025-03-31","type":1,"releaseDate":1742972401256},{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Binance Will Delist AERGO, AST, BURGER, COMBO, LINA on 2025-03-28","type":1,"releaseDate":1742536220352},{"id":229830,"code":"69ff9abd38ad4cfcbe4521f654278a7d","title":"Notice of Removal of Spot Trading Pairs - 2025-03-21","type":1,"releaseDate":1742356810621},{"id":229618,"code":"edf76712d2ea48f8916a32cfe1b82fb9","title":"Notice of Removal of Margin Trading Pairs - 2025-03-25","type":1,"releaseDate":1742266815394},{"id":228973,"code":"4b88b1f8848444d9ad7af3d406bff72e","title":"Notice of Removal of Spot Trading Pairs - 2025-03-14","type":1,"releaseDate":1741770011825},{"id":228025,"code":"820e86ea4d5145a1bc357682394552ba","title":"Notice of Removal of Spot Trading Pairs - 2025-03-07","type":1,"releaseDate":1741140001767},{"id":227872,"code":"487e8345ab8146bba30ce251e2f9f974","title":"Notice of Removal of Margin Trading Pairs - 2025-03-11","type":1,"releaseDate":1741060808105},{"id":227184,"code":"7600776423b74af5a8716354b0cdef8b","title":"Notice of Removal of Spot Trading Pairs - 2025-02-28","type":1,"releaseDate":1740546019347},{"id":226679,"code":"0d93139d71c64f74bd63749c141842fb","title":"Binance Earn: Notice on Removal of Dual Investment Token Pairs - 2025-02-21","type":1,"releaseDate":1740027606855},{"id":226537,"code":"d3f0e61ac6d942c98ede2cfeade10314","title":"Notice of Removal of Spot Trading Pairs - 2025-02-21","type":1,"releaseDate":1739937608036}],"catalogs":[]}]},"success":true}
    """

count = 0


class MyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global count
        count += 1
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        result = ""
        if count % 3 == 0:
            self.send_response(403)
            return
        elif count % 13 == 0:
            result = DELISTING
        elif count % 5 == 0:
            result = NO_MARKERS_IN_TEXT
        elif count % 7 == 0:
            result = NO_COINS_IN_ANNOUNCE
        else:
            result = FIRST_RESPONSE

        self.wfile.write(result.replace("777777", str(count)).encode())


PORT = 8765

with socketserver.TCPServer(("", PORT), MyHandler) as httpd:
    print("serving at port", PORT)
    httpd.serve_forever()
