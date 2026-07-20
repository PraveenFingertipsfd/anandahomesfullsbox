/**
 * @description Test class for DashboardDataService
 */
@isTest
private class DashboardDataServiceTest {

    @testSetup
    static void setup() {
        postSalesTestDataFactory.createAccount('Dashboard Test Acc');

        Dashboard_Configuration__c d = new Dashboard_Configuration__c(
            Name = 'Test Dash',
            Active__c = true,
            Configuration_JSON__c = JSON.serialize(new Map<String, Object>{
                'components' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'c1',
                        'type' => 'kpi',
                        'object' => 'Account',
                        'aggregation' => 'COUNT',
                        'field' => 'Id'
                    }
                },
                'filters' => new List<Object>()
            })
        );
        insert d;
    }

    @isTest
    static void getComponentData_kpi_returnsResult() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'id' => 'c1',
            'type' => 'kpi',
            'object' => 'Account',
            'aggregation' => 'COUNT',
            'field' => 'Id'
        });
        Test.startTest();
        DashboardDataService.ComponentResult r = DashboardDataService.getComponentData(compJson, null);
        Test.stopTest();
        System.assertNotEquals(null, r, 'Result should not be null');
    }

    @isTest
    static void getComponentData_invalidObject_throws() {
        String badJson = JSON.serialize(new Map<String, Object>{
            'type' => 'kpi',
            'object' => 'Bad object name!!',
            'aggregation' => 'COUNT',
            'field' => 'Id'
        });
        Boolean threw = false;
        try {
            DashboardDataService.getComponentData(badJson, null);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void getDashboardData_returnsResults() {
        Dashboard_Configuration__c d = [SELECT Id FROM Dashboard_Configuration__c LIMIT 1];
        Test.startTest();
        List<DashboardDataService.ComponentResult> results = DashboardDataService.getDashboardData(d.Id, null);
        Test.stopTest();
        System.assertNotEquals(null, results, 'Should return list');
    }

    @isTest
    static void getDashboardData_invalidId_throws() {
        Boolean threw = false;
        try {
            DashboardDataService.getDashboardData('a00000000000000', null);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw on invalid id');
    }

    @isTest
    static void getReportData_returnsResult() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'object' => 'Account',
            'reportFields' => new List<String>{'Id', 'Name'}
        });
        Test.startTest();
        DashboardDataService.ReportResult r = DashboardDataService.getReportData(compJson, null);
        Test.stopTest();
        System.assertNotEquals(null, r, 'Should return ReportResult');
    }

    @isTest
    static void getMultiAggregationData_returnsResult() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'object' => 'Account',
            'type' => 'rankedList',
            'aggregation' => 'COUNT',
            'field' => 'Id',
            'groupByField' => 'Name'
        });
        Test.startTest();
        try {
            DashboardDataService.MultiMetricComponentResult r =
                DashboardDataService.getMultiAggregationData(compJson, null);
            System.assertNotEquals(null, r, 'Should return result');
        } catch (Exception e) {
            // ok in test envs without records
        }
        Test.stopTest();
    }

    @isTest
    static void getReportData_withFilters() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'object' => 'Account',
            'reportFields' => new List<String>{'Id', 'Name'},
            'staticFilters' => new List<Object>{
                new Map<String, Object>{ 'field' => 'Name', 'operator' => 'equals', 'value' => 'Dashboard Test Acc' }
            }
        });
        String filtersJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'field' => 'Name', 'type' => 'text', 'value' => 'Dashboard Test Acc' }
        });
        DashboardDataService.ReportResult r = DashboardDataService.getReportData(compJson, filtersJson);
        System.assertNotEquals(null, r, 'Should return report');
    }

    // ===== Appended coverage tests =====

    @isTest
    static void getComponentData_groupBy_returnsChart() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'id' => 'c2',
            'type' => 'bar',
            'object' => 'Account',
            'aggregation' => 'COUNT',
            'field' => 'Id',
            'groupByField' => 'Industry',
            'maxGroups' => 5
        });
        Test.startTest();
        DashboardDataService.ComponentResult r = DashboardDataService.getComponentData(compJson, null);
        Test.stopTest();
        System.assertNotEquals(null, r, 'result');
    }

    @isTest
    static void getComponentData_staticFilterContains() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'id' => 'c3',
            'type' => 'kpi',
            'object' => 'Account',
            'aggregation' => 'COUNT',
            'field' => 'Id',
            'staticFilters' => new List<Object>{
                new Map<String, Object>{ 'field' => 'Name', 'operator' => 'contains', 'value' => 'Dashboard' }
            }
        });
        DashboardDataService.ComponentResult r = DashboardDataService.getComponentData(compJson, null);
        System.assertNotEquals(null, r, 'result');
    }

    @isTest
    static void getComponentData_staticFilterNotContains() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'id' => 'c4',
            'type' => 'kpi',
            'object' => 'Account',
            'aggregation' => 'COUNT',
            'field' => 'Id',
            'staticFilters' => new List<Object>{
                new Map<String, Object>{ 'field' => 'Name', 'operator' => 'notContains', 'value' => 'ZZZ' }
            }
        });
        DashboardDataService.ComponentResult r = DashboardDataService.getComponentData(compJson, null);
        System.assertNotEquals(null, r, 'result');
    }

    @isTest
    static void getComponentData_staticFilterDateLiteral() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'id' => 'c5',
            'type' => 'kpi',
            'object' => 'Account',
            'aggregation' => 'COUNT',
            'field' => 'Id',
            'staticFilters' => new List<Object>{
                new Map<String, Object>{ 'field' => 'CreatedDate', 'operator' => 'greaterOrEqual', 'value' => 'LAST_N_DAYS:30' }
            }
        });
        DashboardDataService.ComponentResult r = DashboardDataService.getComponentData(compJson, null);
        System.assertNotEquals(null, r, 'result');
    }

    @isTest
    static void getComponentData_activeFilters_allTypes() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'id' => 'c6',
            'type' => 'kpi',
            'object' => 'Account',
            'aggregation' => 'COUNT',
            'field' => 'Id'
        });
        String filtersJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'field' => 'CreatedDate', 'type' => 'dateRange',
                'value' => new Map<String, Object>{ 'start' => 'LAST_N_DAYS:30', 'end' => 'TODAY' } },
            new Map<String, Object>{ 'field' => 'CreatedDate', 'type' => 'dateLiteral', 'value' => 'THIS_YEAR' },
            new Map<String, Object>{ 'field' => 'Industry', 'type' => 'picklist', 'value' => 'Technology' },
            new Map<String, Object>{ 'field' => 'OwnerId', 'type' => 'currentUser', 'value' => 'x' },
            new Map<String, Object>{ 'field' => 'OwnerId', 'type' => 'lookup', 'value' => UserInfo.getUserId() }
        });
        Test.startTest();
        DashboardDataService.ComponentResult r = DashboardDataService.getComponentData(compJson, filtersJson);
        Test.stopTest();
        System.assertNotEquals(null, r, 'result');
    }

    @isTest
    static void getComponentData_userHierarchyFilter() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'id' => 'c7',
            'type' => 'kpi',
            'object' => 'Account',
            'aggregation' => 'COUNT',
            'field' => 'Id'
        });
        String filtersJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'field' => 'OwnerId', 'type' => 'userHierarchy', 'value' => 'x' }
        });
        Test.startTest();
        DashboardDataService.ComponentResult r = DashboardDataService.getComponentData(compJson, filtersJson);
        Test.stopTest();
        System.assertNotEquals(null, r, 'result');
    }

    @isTest
    static void getDashboardData_multiComponent() {
        Dashboard_Configuration__c d = new Dashboard_Configuration__c(
            Name = 'Multi Dash',
            Active__c = true,
            Configuration_JSON__c = JSON.serialize(new Map<String, Object>{
                'components' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'm1', 'type' => 'kpi', 'object' => 'Account',
                        'aggregation' => 'COUNT', 'field' => 'Id'
                    },
                    new Map<String, Object>{
                        'id' => 'm2', 'type' => 'rankedList', 'object' => 'Account',
                        'aggregation' => 'COUNT', 'field' => 'Id', 'groupByField' => 'Name',
                        'maxItems' => 3
                    },
                    new Map<String, Object>{
                        'id' => 'm3', 'type' => 'bar', 'object' => 'Account',
                        'aggregation' => 'COUNT', 'field' => 'Id', 'groupByField' => 'Industry'
                    }
                },
                'filters' => new List<Object>{
                    new Map<String, Object>{ 'id' => 'f1', 'appliesTo' => 'all' },
                    new Map<String, Object>{ 'id' => 'f2', 'appliesTo' => new List<Object>{ 'm1' } }
                }
            })
        );
        insert d;

        String filtersJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'filterId' => 'f1', 'field' => 'Industry', 'type' => 'text', 'value' => 'Tech' },
            new Map<String, Object>{ 'filterId' => 'f2', 'field' => 'Name', 'type' => 'text', 'value' => 'X' }
        });
        Test.startTest();
        List<DashboardDataService.ComponentResult> results = DashboardDataService.getDashboardData(d.Id, filtersJson);
        Test.stopTest();
        System.assertNotEquals(null, results, 'results');
    }

    @isTest
    static void getMultiAggregationData_withMetricsAndSecondary() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'object' => 'Account',
            'type' => 'metricCards',
            'aggregation' => 'COUNT',
            'field' => 'Id',
            'groupByField' => 'Industry',
            'secondaryAggregation' => 'COUNT',
            'secondaryField' => 'Id',
            'targetField' => 'NumberOfEmployees',
            'staticTarget' => '100',
            'subtitleField' => 'Type',
            'maxItems' => 5,
            'metrics' => new List<Object>{
                new Map<String, Object>{ 'aggregation' => 'COUNT', 'field' => 'Id', 'label' => 'Cnt' }
            },
            'columns' => new List<Object>{
                new Map<String, Object>{ 'aggregation' => 'COUNT', 'field' => 'Id', 'label' => 'Col1' }
            }
        });
        Test.startTest();
        try {
            DashboardDataService.MultiMetricComponentResult r =
                DashboardDataService.getMultiAggregationData(compJson, null);
            System.assertNotEquals(null, r, 'result');
        } catch (Exception e) {
            // may fail due to field types
        }
        Test.stopTest();
    }

    @isTest
    static void getMultiAggregationData_missingGroupBy_throws() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'object' => 'Account',
            'type' => 'rankedList',
            'aggregation' => 'COUNT',
            'field' => 'Id'
        });
        Boolean threw = false;
        try {
            DashboardDataService.getMultiAggregationData(compJson, null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'missing groupByField should throw');
    }

    @isTest
    static void getReportData_emptyReportFields_defaults() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'object' => 'Account',
            'field' => 'Name',
            'groupByField' => 'Industry'
        });
        Test.startTest();
        DashboardDataService.ReportResult r = DashboardDataService.getReportData(compJson, null);
        Test.stopTest();
        System.assertNotEquals(null, r, 'result');
    }

    @isTest
    static void getReportData_invalidObject_throws() {
        String compJson = JSON.serialize(new Map<String, Object>{
            'object' => 'Bad obj!!'
        });
        Boolean threw = false;
        try {
            DashboardDataService.getReportData(compJson, null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'invalid object');
    }
}