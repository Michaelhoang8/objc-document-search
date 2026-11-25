#import <Foundation/Foundation.h>
#include <math.h>

static void Require(BOOL value, NSString *message) {
    if (!value) [NSException raise:@"ValidationError" format:@"%@", message];
}

static NSArray<NSString *> *Tokens(NSString *text) {
    NSString *normal = [[text precomposedStringWithCanonicalMapping] lowercaseString];
    NSArray *parts = [normal componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *part in parts) if (part.length) [result addObject:part];
    return result;
}

@interface SearchIndex : NSObject
@property(nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *postings;
@property(nonatomic) NSMutableDictionary<NSString *, NSNumber *> *lengths;
@property(nonatomic) double averageLength;
- (instancetype)initWithDocuments:(NSArray *)documents;
- (NSArray<NSDictionary *> *)search:(NSString *)query;
@end

@implementation SearchIndex
- (instancetype)initWithDocuments:(NSArray *)documents {
    self = [super init];
    if (self) {
        Require([documents isKindOfClass:[NSArray class]], @"Input must be an array.");
        _postings = [NSMutableDictionary dictionary];
        _lengths = [NSMutableDictionary dictionary];
        NSUInteger total = 0;
        for (id item in documents) {
            Require([item isKindOfClass:[NSDictionary class]], @"Each document must be an object.");
            NSDictionary *document = item;
            id identifier = document[@"id"], text = document[@"text"];
            Require([identifier isKindOfClass:[NSString class]] && [identifier length] > 0, @"Document ID must be a nonempty string.");
            Require([text isKindOfClass:[NSString class]], @"Document text must be a string.");
            Require(_lengths[identifier] == nil, @"Duplicate document ID.");
            NSArray *tokens = Tokens(text);
            _lengths[identifier] = @(tokens.count);
            total += tokens.count;
            for (NSString *token in tokens) {
                if (!_postings[token]) _postings[token] = [NSMutableDictionary dictionary];
                _postings[token][identifier] = @([_postings[token][identifier] unsignedIntegerValue] + 1);
            }
        }
        _averageLength = documents.count ? (double)total / documents.count : 0;
    }
    return self;
}
- (NSArray<NSDictionary *> *)search:(NSString *)query {
    // OR retrieval with BM25 ranking. Repeated query words count once.
    NSArray *terms = [[[NSSet setWithArray:Tokens(query)] allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableDictionary<NSString *, NSNumber *> *scores = [NSMutableDictionary dictionary];
    for (NSString *term in terms) {
        NSDictionary *documents = self.postings[term];
        if (!documents.count) continue;
        double idf = log(1.0 + (self.lengths.count - documents.count + 0.5) / (documents.count + 0.5));
        for (NSString *identifier in documents) {
            double tf = [documents[identifier] doubleValue];
            double length = [self.lengths[identifier] doubleValue];
            double score = idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * length / self.averageLength));
            scores[identifier] = @([scores[identifier] doubleValue] + score);
        }
    }
    NSArray *ids = [[scores allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult scoreOrder = [scores[b] compare:scores[a]];
        return scoreOrder == NSOrderedSame ? [a compare:b] : scoreOrder;
    }];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *identifier in ids) [result addObject:@{@"id":identifier, @"score":scores[identifier]}];
    return result;
}
@end

static void Tests(void) {
    SearchIndex *index = [[SearchIndex alloc] initWithDocuments:@[
        @{@"id":@"a", @"text":@"alpha alpha beta"},
        @{@"id":@"b", @"text":@"alpha gamma"},
        @{@"id":@"c", @"text":@""}]];
    NSArray *results = [index search:@"ALPHA"];
    Require(results.count == 2, @"retrieval count");
    Require([results[0][@"id"] isEqual:@"a"], @"term-frequency ranking");
    Require([results[0][@"score"] doubleValue] > [results[1][@"score"] doubleValue], @"score ordering");
    Require([[index search:@"alpha alpha"] isEqual:results], @"query deduplication");
    Require([index search:@"unknown"].count == 0, @"unknown term");
    Require([index search:@" ... "].count == 0, @"empty query");
    Require([Tokens(@"CAFÉ cafe\u0301") isEqual:@[@"café", @"café"]], @"canonical Unicode normalization");
    SearchIndex *ties = [[SearchIndex alloc] initWithDocuments:@[@{@"id":@"z", @"text":@"x"},@{@"id":@"a", @"text":@"x"}]];
    Require([ties search:@"x"][0][@"id"] && [[ties search:@"x"][0][@"id"] isEqual:@"a"], @"stable ties");
    Require([[[SearchIndex alloc] initWithDocuments:@[]] search:@"x"].count == 0, @"empty corpus");
    BOOL rejected = NO;
    @try { (void)[[SearchIndex alloc] initWithDocuments:@[@{@"id":@"a", @"text":@"x"},@{@"id":@"a", @"text":@"y"}]]; }
    @catch (NSException *error) { rejected = YES; }
    Require(rejected, @"duplicate IDs rejected");
    puts("10 search checks passed");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        @try {
            if (argc == 2 && strcmp(argv[1], "--test") == 0) { Tests(); return 0; }
            if (argc != 3 || strcmp(argv[1], "--help") == 0) {
                puts("Usage: ./document-search documents.json 'query words' | --test");
                return argc == 2 && strcmp(argv[1], "--help") == 0 ? 0 : 2;
            }
            NSError *error = nil;
            NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] options:0 error:&error];
            Require(data != nil, error.localizedDescription ?: @"Cannot read input.");
            id documents = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            Require(documents != nil, error.localizedDescription ?: @"Invalid JSON.");
            SearchIndex *index = [[SearchIndex alloc] initWithDocuments:documents];
            NSArray *results = [index search:[NSString stringWithUTF8String:argv[2]]];
            NSData *output = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
            Require(output != nil, @"Cannot encode scores.");
            puts([[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding].UTF8String);
            return 0;
        } @catch (NSException *error) { fprintf(stderr, "%s\n", error.reason.UTF8String); return 1; }
    }
}
