GET https://api-manager.upbit.com/api/v1/announcements?os=web&page=1&per_page=20&category=all
HTTP 200
[Asserts]
jsonpath "$.success" == true
jsonpath "$.data.total_pages" > 200

GET https://api-manager.upbit.com/api/v1/announcements?os=android&page=1&per_page=7&category=all
HTTP 200
[Asserts]
jsonpath "$.success" == true
jsonpath "$.data.total_pages" > 200

