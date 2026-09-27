# Performance Testing Results



## Objective



Performance testing was carried out to evaluate the response time and stability of the SnapSync AI backend API under normal and concurrent request conditions.



The public studio endpoint was selected because it is a read-only endpoint and does not modify booking, customer, or studio data.



## Test Environment



- Application: SnapSync AI - Intelligent Photography Booking & Management Platform

- Backend: ASP.NET Core (.NET 8)

- Database: PostgreSQL

- Test Endpoint: GET /api/public/studios

- Backend URL: http://localhost:5284

- Environment: Local development environment



## Test 1 - Initial Request



A single request was sent to the public studios endpoint.



- Response Time: 329.94 ms

- Result: Successful



This request was measured separately before the repeated-request tests.



## Test 2 - Sequential Requests



50 requests were sent sequentially to the public studios endpoint.



Results:



- Total Requests: 50

- Successful Requests: 50

- Failed Requests: 0

- Success Rate: 100%

- Average Response Time: 16.67 ms

- Minimum Response Time: 8.71 ms

- Maximum Response Time: 42.77 ms



The API successfully handled all sequential requests without failures.



## Test 3 - Concurrent Load Test



A concurrent load test was performed using 10 workers, with each worker sending 5 requests.



Results:



- Total Requests: 50

- Concurrent Workers: 10

- Successful Requests: 50

- Failed Requests: 0

- Success Rate: 100%

- Average Response Time: 31.44 ms

- Minimum Response Time: 3.37 ms

- Maximum Response Time: 169.39 ms



All concurrent requests completed successfully. Response times increased under concurrent access compared with the sequential test, but no request failures were observed.



## Conclusion



The tested public API endpoint remained stable during the local performance tests. Both the sequential and concurrent tests completed with a 100% success rate.



These results represent controlled testing in the local development environment and should not be interpreted as production-scale load or stress testing.


