#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["ipython", "websockets", "loguru"]
# ///
import http.server
import socketserver
import time

# catalog id story
# FIRST_RESPONSE = """
# {"code":"000000","message":null,"messageDetail":null,"data":{"catalogs":[{"catalogId":161,"parentCatalogId":null,"icon":"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png","catalogName":"Delisting","description":null,"catalogType":1,"total":777777,"articles":[{"id":208595,"code":"84d4dc37762944828f3e91c4eabb6bb6","title":"Notice of Removal of Spot Trading Pairs - 2024-08-23","type":1,"releaseDate":1724223602529},{"id":207854,"code":"f881d01a7e5f42cf9432b733ca355513","title":"Notice of Removal of Spot Trading Pairs - 2024-08-16","type":1,"releaseDate":1723611608432},{"id":207839,"code":"865c4e7e31b34b9bb439044d97414273","title":"Notice of Removal of Margin Trading Pairs - 2024-08-22","type":1,"releaseDate":1723608007883},{"id":207063,"code":"e2fcd2c945654c8d832395335429403e","title":"Binance Will Delist CVP, EPX, FOR, LOOM, REEF, VGX on 2024-08-26","type":1,"releaseDate":1723446011329},{"id":206836,"code":"e633a048a38a44c29828a441e4c4dac2","title":"Notice of Removal of Spot Trading Pairs - 2024-08-02","type":1,"releaseDate":1722409208662}],"catalogs":[]}]},"success":true}
#     """
# DELISTING = """
# {"code":"000000","message":null,"messageDetail":null,"data":{"catalogs":[{"catalogId":161,"parentCatalogId":null,"icon":"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png","catalogName":"Delisting","description":null,"catalogType":1,"total":777777,"articles":[{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Binance Will Delist AERGO, AST, BURGER, COMBO, LINA on 2025-03-28","type":1,"releaseDate":1742536227777},{"id":230884,"code":"77c21bfbaec349c18709d6c49a49e03b","title":"Notice of Removal of Spot Trading Pairs - 2025-03-28 & 2025-03-31","type":1,"releaseDate":1742972401256},{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Binance Will Delist AERGO, AST, BURGER, COMBO, LINA on 2025-03-28","type":1,"releaseDate":1742536220352},{"id":229830,"code":"69ff9abd38ad4cfcbe4521f654278a7d","title":"Notice of Removal of Spot Trading Pairs - 2025-03-21","type":1,"releaseDate":1742356810621},{"id":229618,"code":"edf76712d2ea48f8916a32cfe1b82fb9","title":"Notice of Removal of Margin Trading Pairs - 2025-03-25","type":1,"releaseDate":1742266815394},{"id":228973,"code":"4b88b1f8848444d9ad7af3d406bff72e","title":"Notice of Removal of Spot Trading Pairs - 2025-03-14","type":1,"releaseDate":1741770011825},{"id":228025,"code":"820e86ea4d5145a1bc357682394552ba","title":"Notice of Removal of Spot Trading Pairs - 2025-03-07","type":1,"releaseDate":1741140001767},{"id":227872,"code":"487e8345ab8146bba30ce251e2f9f974","title":"Notice of Removal of Margin Trading Pairs - 2025-03-11","type":1,"releaseDate":1741060808105},{"id":227184,"code":"7600776423b74af5a8716354b0cdef8b","title":"Notice of Removal of Spot Trading Pairs - 2025-02-28","type":1,"releaseDate":1740546019347},{"id":226679,"code":"0d93139d71c64f74bd63749c141842fb","title":"Binance Earn: Notice on Removal of Dual Investment Token Pairs - 2025-02-21","type":1,"releaseDate":1740027606855},{"id":226537,"code":"d3f0e61ac6d942c98ede2cfeade10314","title":"Notice of Removal of Spot Trading Pairs - 2025-02-21","type":1,"releaseDate":1739937608036}],"catalogs":[]}]},"success":true}
#     """
#
# # # no important markers
# NO_MARKERS_IN_TEXT = """
# {"code":"000000","message":null,"messageDetail":null,"data":{"catalogs":[{"catalogId":161,"parentCatalogId":null,"icon":"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png","catalogName":"Delisting","description":null,"catalogType":1,"total":777777,"articles":[{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Someone will send me AERGO, AST, BURGER, COMBO, LINA tomorrow","type":1,"releaseDate":1742536227777},{"id":230884,"code":"77c21bfbaec349c18709d6c49a49e03b","title":"Notice of Removal of Spot Trading Pairs - 2025-03-28 & 2025-03-31","type":1,"releaseDate":1742972401256},{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Binance Will Delist AERGO, AST, BURGER, COMBO, LINA on 2025-03-28","type":1,"releaseDate":1742536220352},{"id":229830,"code":"69ff9abd38ad4cfcbe4521f654278a7d","title":"Notice of Removal of Spot Trading Pairs - 2025-03-21","type":1,"releaseDate":1742356810621},{"id":229618,"code":"edf76712d2ea48f8916a32cfe1b82fb9","title":"Notice of Removal of Margin Trading Pairs - 2025-03-25","type":1,"releaseDate":1742266815394},{"id":228973,"code":"4b88b1f8848444d9ad7af3d406bff72e","title":"Notice of Removal of Spot Trading Pairs - 2025-03-14","type":1,"releaseDate":1741770011825},{"id":228025,"code":"820e86ea4d5145a1bc357682394552ba","title":"Notice of Removal of Spot Trading Pairs - 2025-03-07","type":1,"releaseDate":1741140001767},{"id":227872,"code":"487e8345ab8146bba30ce251e2f9f974","title":"Notice of Removal of Margin Trading Pairs - 2025-03-11","type":1,"releaseDate":1741060808105},{"id":227184,"code":"7600776423b74af5a8716354b0cdef8b","title":"Notice of Removal of Spot Trading Pairs - 2025-02-28","type":1,"releaseDate":1740546019347},{"id":226679,"code":"0d93139d71c64f74bd63749c141842fb","title":"Binance Earn: Notice on Removal of Dual Investment Token Pairs - 2025-02-21","type":1,"releaseDate":1740027606855},{"id":226537,"code":"d3f0e61ac6d942c98ede2cfeade10314","title":"Notice of Removal of Spot Trading Pairs - 2025-02-21","type":1,"releaseDate":1739937608036}],"catalogs":[]}]},"success":true}
#     """
# # no coins
# NO_COINS_IN_ANNOUNCE = """
# {"code":"000000","message":null,"messageDetail":null,"data":{"catalogs":[{"catalogId":161,"parentCatalogId":null,"icon":"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png","catalogName":"Delisting","description":null,"catalogType":1,"total":777777,"articles":[{"id":230884,"code":"77c21bfbaec349c18709d6c49a49e03b","title":"Notice of Removal of Spot Trading Pairs - 2025-03-28 & 2025-03-31","type":1,"releaseDate":1742972401256},{"id":230166,"code":"db7ad1c7aa6248cda735102cdcdc4b8d","title":"Binance Will Delist AERGO, AST, BURGER, COMBO, LINA on 2025-03-28","type":1,"releaseDate":1742536220352},{"id":229830,"code":"69ff9abd38ad4cfcbe4521f654278a7d","title":"Notice of Removal of Spot Trading Pairs - 2025-03-21","type":1,"releaseDate":1742356810621},{"id":229618,"code":"edf76712d2ea48f8916a32cfe1b82fb9","title":"Notice of Removal of Margin Trading Pairs - 2025-03-25","type":1,"releaseDate":1742266815394},{"id":228973,"code":"4b88b1f8848444d9ad7af3d406bff72e","title":"Notice of Removal of Spot Trading Pairs - 2025-03-14","type":1,"releaseDate":1741770011825},{"id":228025,"code":"820e86ea4d5145a1bc357682394552ba","title":"Notice of Removal of Spot Trading Pairs - 2025-03-07","type":1,"releaseDate":1741140001767},{"id":227872,"code":"487e8345ab8146bba30ce251e2f9f974","title":"Notice of Removal of Margin Trading Pairs - 2025-03-11","type":1,"releaseDate":1741060808105},{"id":227184,"code":"7600776423b74af5a8716354b0cdef8b","title":"Notice of Removal of Spot Trading Pairs - 2025-02-28","type":1,"releaseDate":1740546019347},{"id":226679,"code":"0d93139d71c64f74bd63749c141842fb","title":"Binance Earn: Notice on Removal of Dual Investment Token Pairs - 2025-02-21","type":1,"releaseDate":1740027606855},{"id":226537,"code":"d3f0e61ac6d942c98ede2cfeade10314","title":"Notice of Removal of Spot Trading Pairs - 2025-02-21","type":1,"releaseDate":1739937608036}],"catalogs":[]}]},"success":true}
#     """
#
# full catalog story

PRIMARY_RESPONSE = """
{
  "code": "000000",
  "message": null,
  "messageDetail": null,
  "data": {
    "catalogs": [
      {
        "catalogId": 48,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/d3201bf0be35bb246b65a767221410e0.png",
        "catalogName": "New Cryptocurrency Listing",
        "description": null,
        "catalogType": 1,
        "total": 1821,
        "articles": [
          {
            "id": 240045,
            "code": "3417fdb6e4cc498bbcb21f612ae9bd9b",
            "title": "Binance Will Add Sahara AI (SAHARA) on Earn, Buy Crypto, Convert, Margin & Futures",
            "type": 1,
            "releaseDate": 1750937414029
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 49,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/1c644f6be4cad5a1c149e7318d85e9ff.png",
        "catalogName": "Latest Binance News",
        "description": null,
        "catalogType": 1,
        "total": 3875,
        "articles": [
          {
            "id": 240165,
            "code": "9103c4fbee38406699d269089ecac615",
            "title": "Introducing Dymension (DYM) on BNSOL Super Stake: HODL BNSOL & DeFi BNSOL Assets to Get DYM APR Boost Airdrop Rewards",
            "type": 1,
            "releaseDate": 1751256001367
          },
          {
            "id": 240127,
            "code": "c1addac5267d4efb816b5b603712b77f",
            "title": "Binance Will Update the Collateral Ratio of Multiple Assets Under Portfolio Margin (2025-07-04)",
            "type": 1,
            "releaseDate": 1751208278529
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 93,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/e15292967d819d422e0bab0a6389797b.png",
        "catalogName": "Latest Activities",
        "description": null,
        "catalogType": 1,
        "total": 2161,
        "articles": [
          {
            "id": 240343,
            "code": "0e6e95c9cfec426e8d7a26ec84fcf7b6",
            "title": "BugsCoin Trading Competition: Trade BugsCoin (BGSC) and Share About $1M Worth of Rewards",
            "type": 1,
            "releaseDate": 1751358614806
          },
          {
            "id": 240301,
            "code": "dea7bf83ae0a4acea39fd643c3b782d1",
            "title": "Binance Earn July Monthly Challenge: Enjoy Up to 3,600 USDC Rewards and 33.65% APR on Dual Investment",
            "type": 1,
            "releaseDate": 1751346036623
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 50,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/0740492d102095f580ba46a2aa056bb8.png",
        "catalogName": "New Fiat Listings",
        "description": null,
        "catalogType": 1,
        "total": 203,
        "articles": [
          {
            "id": 157880,
            "code": "618d5054d6c542508e610b212006139e",
            "title": "Buy ARB, ID, RDNT, TUSD & USDC Directly Using Credit/Debit Cards and Fiat Balances",
            "type": 1,
            "releaseDate": 1681824612744
          },
          {
            "id": 147462,
            "code": "62e08665050045e28a3db5e92cc18323",
            "title": "BADGER Available via Credit/Debit Card",
            "type": 1,
            "releaseDate": 1674195307030
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 161,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/a6322b2e7d81faf3f65a6d14c372995e.png",
        "catalogName": "Delisting",
        "description": null,
        "catalogType": 1,
        "total": 266,
        "articles": [
          {
            "id": 239847,
            "code": "a37e284394114daf8e0045360dd129eb",
            "title": "Notice of Removal of Spot Trading Pairs - 2025-06-27",
            "type": 1,
            "releaseDate": 1750831206996
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 157,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/e4eea861bcbce3a1333de7cb07bdb059.png",
        "catalogName": "Maintenance Updates",
        "description": null,
        "catalogType": 1,
        "total": 388,
        "articles": [
          {
            "id": 240267,
            "code": "25bb827091a8487691b4a1cd3e65ba11",
            "title": "Binance Will Support the Vechain (VET) and VeThor Token (VTHO) Network Upgrade & Hard Fork - 2025-07-01",
            "type": 1,
            "releaseDate": 1751337018929
          },
          {
            "id": 240208,
            "code": "30fe3186ed56470d8eb98e65e1a50c10",
            "title": "Binance Will Support the Polygon (POL) Network Upgrade & Hard Fork - 2025-07-01",
            "type": 1,
            "releaseDate": 1751270401227
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 51,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/2831e38ac3f498dab0516159076eafa6.png",
        "catalogName": "API Updates",
        "description": null,
        "catalogType": 1,
        "total": 77,
        "articles": [
          {
            "id": 215285,
            "code": "37f316ef883f4f739ba2cc821a3002fb",
            "title": "Binance Futures API Updates (2024-10-30)",
            "type": 1,
            "releaseDate": 1729591223290
          },
          {
            "id": 214867,
            "code": "753c0ebc710c4084a06a845dd959dd6f",
            "title": "Binance Earn Enables API Functionality for SOL Staking",
            "type": 1,
            "releaseDate": 1729216807163
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 128,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/f3881542ca77a32715dca40926277add.png",
        "catalogName": "Crypto Airdrop",
        "description": null,
        "catalogType": 1,
        "total": 49,
        "articles": [
          {
            "id": 238891,
            "code": "4faf095125404d75b5a742e758a5df32",
            "title": "Solayer (LAYER) Airdrop Continues: Second Binance HODLer Airdrops Announced – Earn LAYER With Retroactive BNB Simple Earn Subscriptions (2025-06-16)",
            "type": 1,
            "releaseDate": 1750055401345
          },
          {
            "id": 236019,
            "code": "808c283c23af4162af706c97fbc207a9",
            "title": "Binance Will Support the Doodles (DOOD) Airdrop for MUBARAK, BROCCOLI714, TST, 1MBABYDOGE, and KOMA Holders",
            "type": 1,
            "releaseDate": 1746759601247
          }
        ],
        "catalogs": []
      }
    ]
  },
  "success": true
}
"""

RANDOM_UPDATE_RESPONSE = """
{
  "code": "000000",
  "message": null,
  "messageDetail": null,
  "data": {
    "catalogs": [
      {
        "catalogId": 48,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/d3201bf0be35bb246b65a767221410e0.png",
        "catalogName": "New Cryptocurrency Listing",
        "description": null,
        "catalogType": 1,
        "total": 1821,
        "articles": [
          {
            "id": 240186,
            "code": "fb8600ebb2ae4e80a0db1945e683993c",
            "title": "Notice on New Trading Pairs & Trading Bots Services on Binance Spot - 2025-07-01",
            "type": 1,
            "releaseDate": 1751266801321
          },
          {
            "id": 240045,
            "code": "3417fdb6e4cc498bbcb21f612ae9bd9b",
            "title": "Binance Will Add Sahara AI (SAHARA) on Earn, Buy Crypto, Convert, Margin & Futures",
            "type": 1,
            "releaseDate": 1750937414029
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 49,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/1c644f6be4cad5a1c149e7318d85e9ff.png",
        "catalogName": "Latest Binance News",
        "description": null,
        "catalogType": 1,
        "total": 3875,
        "articles": [
          {
            "id": 240165,
            "code": "9103c4fbee38406699d269089ecac615",
            "title": "Introducing Dymension (DYM) on BNSOL Super Stake: HODL BNSOL & DeFi BNSOL Assets to Get DYM APR Boost Airdrop Rewards",
            "type": 1,
            "releaseDate": 1751256001367
          },
          {
            "id": 240127,
            "code": "c1addac5267d4efb816b5b603712b77f",
            "title": "Binance Will Update the Collateral Ratio of Multiple Assets Under Portfolio Margin (2025-07-04)",
            "type": 1,
            "releaseDate": 1751208278529
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 93,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/e15292967d819d422e0bab0a6389797b.png",
        "catalogName": "Latest Activities",
        "description": null,
        "catalogType": 1,
        "total": 2161,
        "articles": [
          {
            "id": 240343,
            "code": "0e6e95c9cfec426e8d7a26ec84fcf7b6",
            "title": "BugsCoin Trading Competition: Trade BugsCoin (BGSC) and Share About $1M Worth of Rewards",
            "type": 1,
            "releaseDate": 1751358614806
          },
          {
            "id": 240301,
            "code": "dea7bf83ae0a4acea39fd643c3b782d1",
            "title": "Binance Earn July Monthly Challenge: Enjoy Up to 3,600 USDC Rewards and 33.65% APR on Dual Investment",
            "type": 1,
            "releaseDate": 1751346036623
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 50,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/0740492d102095f580ba46a2aa056bb8.png",
        "catalogName": "New Fiat Listings",
        "description": null,
        "catalogType": 1,
        "total": 203,
        "articles": [
          {
            "id": 157880,
            "code": "618d5054d6c542508e610b212006139e",
            "title": "Buy ARB, ID, RDNT, TUSD & USDC Directly Using Credit/Debit Cards and Fiat Balances",
            "type": 1,
            "releaseDate": 1681824612744
          },
          {
            "id": 147462,
            "code": "62e08665050045e28a3db5e92cc18323",
            "title": "BADGER Available via Credit/Debit Card",
            "type": 1,
            "releaseDate": 1674195307030
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 161,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/a6322b2e7d81faf3f65a6d14c372995e.png",
        "catalogName": "Delisting",
        "description": null,
        "catalogType": 1,
        "total": 266,
        "articles": [
          {
            "id": 239847,
            "code": "a37e284394114daf8e0045360dd129eb",
            "title": "Notice of Removal of Spot Trading Pairs - 2025-06-27",
            "type": 1,
            "releaseDate": 1750831206996
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 157,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/e4eea861bcbce3a1333de7cb07bdb059.png",
        "catalogName": "Maintenance Updates",
        "description": null,
        "catalogType": 1,
        "total": 388,
        "articles": [
          {
            "id": 240267,
            "code": "25bb827091a8487691b4a1cd3e65ba11",
            "title": "Binance Will Support the Vechain (VET) and VeThor Token (VTHO) Network Upgrade & Hard Fork - 2025-07-01",
            "type": 1,
            "releaseDate": 1751337018929
          },
          {
            "id": 240208,
            "code": "30fe3186ed56470d8eb98e65e1a50c10",
            "title": "Binance Will Support the Polygon (POL) Network Upgrade & Hard Fork - 2025-07-01",
            "type": 1,
            "releaseDate": 1751270401227
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 51,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/2831e38ac3f498dab0516159076eafa6.png",
        "catalogName": "API Updates",
        "description": null,
        "catalogType": 1,
        "total": 77,
        "articles": [
          {
            "id": 215285,
            "code": "37f316ef883f4f739ba2cc821a3002fb",
            "title": "Binance Futures API Updates (2024-10-30)",
            "type": 1,
            "releaseDate": 1729591223290
          },
          {
            "id": 214867,
            "code": "753c0ebc710c4084a06a845dd959dd6f",
            "title": "Binance Earn Enables API Functionality for SOL Staking",
            "type": 1,
            "releaseDate": 1729216807163
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 128,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/f3881542ca77a32715dca40926277add.png",
        "catalogName": "Crypto Airdrop",
        "description": null,
        "catalogType": 1,
        "total": 49,
        "articles": [
          {
            "id": 238891,
            "code": "4faf095125404d75b5a742e758a5df32",
            "title": "Solayer (LAYER) Airdrop Continues: Second Binance HODLer Airdrops Announced – Earn LAYER With Retroactive BNB Simple Earn Subscriptions (2025-06-16)",
            "type": 1,
            "releaseDate": 1750055401345
          },
          {
            "id": 236019,
            "code": "808c283c23af4162af706c97fbc207a9",
            "title": "Binance Will Support the Doodles (DOOD) Airdrop for MUBARAK, BROCCOLI714, TST, 1MBABYDOGE, and KOMA Holders",
            "type": 1,
            "releaseDate": 1746759601247
          }
        ],
        "catalogs": []
      }
    ]
  },
  "success": true
}
"""

DELISTING_RESPONSE = """
{
  "code": "000000",
  "message": null,
  "messageDetail": null,
  "data": {
    "catalogs": [
      {
        "catalogId": 48,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/d3201bf0be35bb246b65a767221410e0.png",
        "catalogName": "New Cryptocurrency Listing",
        "description": null,
        "catalogType": 1,
        "total": 1821,
        "articles": [
          {
            "id": 240186,
            "code": "fb8600ebb2ae4e80a0db1945e683993c",
            "title": "Notice on New Trading Pairs & Trading Bots Services on Binance Spot - 2025-07-01",
            "type": 1,
            "releaseDate": 1751266801321
          },
          {
            "id": 240045,
            "code": "3417fdb6e4cc498bbcb21f612ae9bd9b",
            "title": "Binance Will Add Sahara AI (SAHARA) on Earn, Buy Crypto, Convert, Margin & Futures",
            "type": 1,
            "releaseDate": 1750937414029
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 49,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/1c644f6be4cad5a1c149e7318d85e9ff.png",
        "catalogName": "Latest Binance News",
        "description": null,
        "catalogType": 1,
        "total": 3875,
        "articles": [
          {
            "id": 240165,
            "code": "9103c4fbee38406699d269089ecac615",
            "title": "Introducing Dymension (DYM) on BNSOL Super Stake: HODL BNSOL & DeFi BNSOL Assets to Get DYM APR Boost Airdrop Rewards",
            "type": 1,
            "releaseDate": 1751256001367
          },
          {
            "id": 240127,
            "code": "c1addac5267d4efb816b5b603712b77f",
            "title": "Binance Will Update the Collateral Ratio of Multiple Assets Under Portfolio Margin (2025-07-04)",
            "type": 1,
            "releaseDate": 1751208278529
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 93,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/e15292967d819d422e0bab0a6389797b.png",
        "catalogName": "Latest Activities",
        "description": null,
        "catalogType": 1,
        "total": 2161,
        "articles": [
          {
            "id": 240343,
            "code": "0e6e95c9cfec426e8d7a26ec84fcf7b6",
            "title": "BugsCoin Trading Competition: Trade BugsCoin (BGSC) and Share About $1M Worth of Rewards",
            "type": 1,
            "releaseDate": 1751358614806
          },
          {
            "id": 240301,
            "code": "dea7bf83ae0a4acea39fd643c3b782d1",
            "title": "Binance Earn July Monthly Challenge: Enjoy Up to 3,600 USDC Rewards and 33.65% APR on Dual Investment",
            "type": 1,
            "releaseDate": 1751346036623
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 50,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/0740492d102095f580ba46a2aa056bb8.png",
        "catalogName": "New Fiat Listings",
        "description": null,
        "catalogType": 1,
        "total": 203,
        "articles": [
          {
            "id": 157880,
            "code": "618d5054d6c542508e610b212006139e",
            "title": "Buy ARB, ID, RDNT, TUSD & USDC Directly Using Credit/Debit Cards and Fiat Balances",
            "type": 1,
            "releaseDate": 1681824612744
          },
          {
            "id": 147462,
            "code": "62e08665050045e28a3db5e92cc18323",
            "title": "BADGER Available via Credit/Debit Card",
            "type": 1,
            "releaseDate": 1674195307030
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 161,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/a6322b2e7d81faf3f65a6d14c372995e.png",
        "catalogName": "Delisting",
        "description": null,
        "catalogType": 1,
        "total": 267,
        "articles": [
          {
            "id": 239906,
            "code": "173b2a63c03141009029407ecfebd14a",
            "title": "Binance Will Delist ALPHA, BSW, KMD, LEVER, LTO on 2025-07-04",
            "type": 1,
            "releaseDate": 1750921209887
          },
          {
            "id": 239847,
            "code": "a37e284394114daf8e0045360dd129eb",
            "title": "Notice of Removal of Spot Trading Pairs - 2025-06-27",
            "type": 1,
            "releaseDate": 1750831206996
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 157,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/e4eea861bcbce3a1333de7cb07bdb059.png",
        "catalogName": "Maintenance Updates",
        "description": null,
        "catalogType": 1,
        "total": 388,
        "articles": [
          {
            "id": 240267,
            "code": "25bb827091a8487691b4a1cd3e65ba11",
            "title": "Binance Will Support the Vechain (VET) and VeThor Token (VTHO) Network Upgrade & Hard Fork - 2025-07-01",
            "type": 1,
            "releaseDate": 1751337018929
          },
          {
            "id": 240208,
            "code": "30fe3186ed56470d8eb98e65e1a50c10",
            "title": "Binance Will Support the Polygon (POL) Network Upgrade & Hard Fork - 2025-07-01",
            "type": 1,
            "releaseDate": 1751270401227
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 51,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/2831e38ac3f498dab0516159076eafa6.png",
        "catalogName": "API Updates",
        "description": null,
        "catalogType": 1,
        "total": 77,
        "articles": [
          {
            "id": 215285,
            "code": "37f316ef883f4f739ba2cc821a3002fb",
            "title": "Binance Futures API Updates (2024-10-30)",
            "type": 1,
            "releaseDate": 1729591223290
          },
          {
            "id": 214867,
            "code": "753c0ebc710c4084a06a845dd959dd6f",
            "title": "Binance Earn Enables API Functionality for SOL Staking",
            "type": 1,
            "releaseDate": 1729216807163
          }
        ],
        "catalogs": []
      },
      {
        "catalogId": 128,
        "parentCatalogId": null,
        "icon": "https://public.bnbstatic.com/image/cms/content/body/202505/f3881542ca77a32715dca40926277add.png",
        "catalogName": "Crypto Airdrop",
        "description": null,
        "catalogType": 1,
        "total": 49,
        "articles": [
          {
            "id": 238891,
            "code": "4faf095125404d75b5a742e758a5df32",
            "title": "Solayer (LAYER) Airdrop Continues: Second Binance HODLer Airdrops Announced – Earn LAYER With Retroactive BNB Simple Earn Subscriptions (2025-06-16)",
            "type": 1,
            "releaseDate": 1750055401345
          },
          {
            "id": 236019,
            "code": "808c283c23af4162af706c97fbc207a9",
            "title": "Binance Will Support the Doodles (DOOD) Airdrop for MUBARAK, BROCCOLI714, TST, 1MBABYDOGE, and KOMA Holders",
            "type": 1,
            "releaseDate": 1746759601247
          }
        ],
        "catalogs": []
      }
    ]
  },
  "success": true
}
"""
count = 0


class MyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.reply()

    def do_POST(self):
        content_length = int(self.headers["Content-Length"])
        self.rfile.read(content_length)
        self.reply()

    def reply(self):
        global count
        count += 1
        if count % 4 == 0:
            self.send_response(403)
            self.end_headers()
            return
        result = ""
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        if count > 13:
            print("delisting")
            result = DELISTING_RESPONSE
            count = 0
        elif count > 10:
            result = "broken"
            time.sleep(0.5)
        # elif count % 5 == 0:
        #     result = ""  # no body
        elif count > 7:
            print("rand update")
            result = RANDOM_UPDATE_RESPONSE
        else:
            result = PRIMARY_RESPONSE
        self.send_header("Content-Length", str(len(result.encode())))
        self.end_headers()

        self.wfile.write(result.encode())


PORT = 8765

with socketserver.TCPServer(("", PORT), MyHandler) as httpd:
    print("serving at port", PORT)
    httpd.serve_forever()
