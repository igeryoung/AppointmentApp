import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:schedule_note_app/cubits/book_list_cubit.dart';
import 'package:schedule_note_app/cubits/book_list_state.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/repositories/book_repository.dart';
import 'package:schedule_note_app/services/book_order_service.dart';

import 'book_list_cubit_test.mocks.dart';

@GenerateMocks([IBookRepository, BookOrderService])
void main() {
  group('BookListCubit', () {
    late MockIBookRepository mockBookRepository;
    late MockBookOrderService mockBookOrderService;
    late BookListCubit cubit;

    final testBook1 = Book(
      id: 1,
      name: 'Test Book 1',
      uuid: 'uuid-1',
      createdAt: DateTime(2024, 1, 1),
    );

    final testBook2 = Book(
      id: 2,
      name: 'Test Book 2',
      uuid: 'uuid-2',
      createdAt: DateTime(2024, 1, 2),
    );

    setUp(() {
      mockBookRepository = MockIBookRepository();
      mockBookOrderService = MockBookOrderService();
      cubit = BookListCubit(mockBookRepository, mockBookOrderService);
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state is BookListInitial', () {
      expect(cubit.state, const BookListInitial());
    });

    group('loadBooks', () {
      blocTest<BookListCubit, BookListState>(
        'emits [BookListLoading, BookListLoaded] when load succeeds',
        build: () {
          when(mockBookRepository.getAll(includeArchived: false))
              .thenAnswer((_) async => [testBook1, testBook2]);
          when(mockBookOrderService.loadBookOrder())
              .thenAnswer((_) async => []);
          when(mockBookOrderService.applyOrder(any, any))
              .thenReturn([testBook1, testBook2]);
          return cubit;
        },
        act: (cubit) => cubit.loadBooks(),
        expect: () => [
          const BookListLoading(),
          BookListLoaded([testBook1, testBook2]),
        ],
        verify: (_) {
          verify(mockBookRepository.getAll(includeArchived: false)).called(1);
          verify(mockBookOrderService.loadBookOrder()).called(1);
          verify(mockBookOrderService.applyOrder(any, any)).called(1);
        },
      );

      blocTest<BookListCubit, BookListState>(
        'emits [BookListLoading, BookListError] when load fails',
        build: () {
          when(mockBookRepository.getAll(includeArchived: false))
              .thenThrow(Exception('Database error'));
          return cubit;
        },
        act: (cubit) => cubit.loadBooks(),
        expect: () => [
          const BookListLoading(),
          const BookListError('Failed to load books: Exception: Database error'),
        ],
      );
    });

    group('createBook', () {
      blocTest<BookListCubit, BookListState>(
        'creates book and reloads list on success',
        build: () {
          when(mockBookRepository.create(any))
              .thenAnswer((_) async => testBook1);
          when(mockBookRepository.getAll(includeArchived: false))
              .thenAnswer((_) async => [testBook1]);
          when(mockBookOrderService.loadBookOrder())
              .thenAnswer((_) async => []);
          when(mockBookOrderService.applyOrder(any, any))
              .thenReturn([testBook1]);
          return cubit;
        },
        act: (cubit) => cubit.createBook('Test Book 1'),
        expect: () => [
          const BookListLoading(),
          BookListLoaded([testBook1]),
        ],
        verify: (_) {
          verify(mockBookRepository.create('Test Book 1')).called(1);
          verify(mockBookRepository.getAll(includeArchived: false)).called(1);
        },
      );

      blocTest<BookListCubit, BookListState>(
        'emits error when book name is empty',
        build: () => cubit,
        act: (cubit) => cubit.createBook(''),
        expect: () => [
          const BookListError('Book name cannot be empty'),
        ],
        verify: (_) {
          verifyNever(mockBookRepository.create(any));
        },
      );

      blocTest<BookListCubit, BookListState>(
        'emits error when create fails',
        build: () {
          when(mockBookRepository.create(any))
              .thenThrow(Exception('Create failed'));
          return cubit;
        },
        act: (cubit) => cubit.createBook('Test Book'),
        expect: () => [
          const BookListError('Failed to create book: Exception: Create failed'),
        ],
      );
    });

    group('updateBook', () {
      blocTest<BookListCubit, BookListState>(
        'updates book and reloads list on success',
        build: () {
          when(mockBookRepository.update(any))
              .thenAnswer((_) async => testBook1);
          when(mockBookRepository.getAll(includeArchived: false))
              .thenAnswer((_) async => [testBook1]);
          when(mockBookOrderService.loadBookOrder())
              .thenAnswer((_) async => []);
          when(mockBookOrderService.applyOrder(any, any))
              .thenReturn([testBook1]);
          return cubit;
        },
        act: (cubit) => cubit.updateBook(testBook1, newName: 'Updated Name'),
        expect: () => [
          const BookListLoading(),
          BookListLoaded([testBook1]),
        ],
        verify: (_) {
          verify(mockBookRepository.update(any)).called(1);
          verify(mockBookRepository.getAll(includeArchived: false)).called(1);
        },
      );

      blocTest<BookListCubit, BookListState>(
        'emits error when book has no ID',
        build: () => cubit,
        act: (cubit) => cubit.updateBook(
          Book(name: 'Test', createdAt: DateTime.now()),
          newName: 'Updated',
        ),
        expect: () => [
          const BookListError('Cannot update book without ID'),
        ],
      );
    });

    group('archiveBook', () {
      blocTest<BookListCubit, BookListState>(
        'archives book and reloads list on success',
        build: () {
          when(mockBookRepository.archive(any))
              .thenAnswer((_) async => {});
          when(mockBookRepository.getAll(includeArchived: false))
              .thenAnswer((_) async => [testBook2]);
          when(mockBookOrderService.loadBookOrder())
              .thenAnswer((_) async => []);
          when(mockBookOrderService.applyOrder(any, any))
              .thenReturn([testBook2]);
          return cubit;
        },
        act: (cubit) => cubit.archiveBook(1),
        expect: () => [
          const BookListLoading(),
          BookListLoaded([testBook2]),
        ],
        verify: (_) {
          verify(mockBookRepository.archive(1)).called(1);
          verify(mockBookRepository.getAll(includeArchived: false)).called(1);
        },
      );
    });

    group('deleteBook', () {
      blocTest<BookListCubit, BookListState>(
        'deletes book and reloads list on success',
        build: () {
          when(mockBookRepository.delete(any))
              .thenAnswer((_) async => {});
          when(mockBookRepository.getAll(includeArchived: false))
              .thenAnswer((_) async => [testBook2]);
          when(mockBookOrderService.loadBookOrder())
              .thenAnswer((_) async => []);
          when(mockBookOrderService.applyOrder(any, any))
              .thenReturn([testBook2]);
          return cubit;
        },
        act: (cubit) => cubit.deleteBook(1),
        expect: () => [
          const BookListLoading(),
          BookListLoaded([testBook2]),
        ],
        verify: (_) {
          verify(mockBookRepository.delete(1)).called(1);
          verify(mockBookRepository.getAll(includeArchived: false)).called(1);
        },
      );

      blocTest<BookListCubit, BookListState>(
        'emits error when delete fails',
        build: () {
          when(mockBookRepository.delete(any))
              .thenThrow(Exception('Delete failed'));
          return cubit;
        },
        act: (cubit) => cubit.deleteBook(1),
        expect: () => [
          const BookListError('Failed to delete book: Exception: Delete failed'),
        ],
      );
    });

    group('reorderBooks', () {
      blocTest<BookListCubit, BookListState>(
        'reorders books and saves order on success',
        build: () {
          when(mockBookOrderService.saveCurrentOrder(any))
              .thenAnswer((_) async => {});
          return cubit;
        },
        seed: () => BookListLoaded([testBook1, testBook2]),
        act: (cubit) => cubit.reorderBooks(0, 2), // ReorderableListView passes 2 to move from 0 to 1
        expect: () => [
          BookListLoaded([testBook2, testBook1]),
        ],
        verify: (_) {
          verify(mockBookOrderService.saveCurrentOrder(any)).called(1);
        },
      );

      blocTest<BookListCubit, BookListState>(
        'does nothing when state is not BookListLoaded',
        build: () => cubit,
        act: (cubit) => cubit.reorderBooks(0, 1),
        expect: () => [],
        verify: (_) {
          verifyNever(mockBookOrderService.saveCurrentOrder(any));
        },
      );

      blocTest<BookListCubit, BookListState>(
        'handles save failure gracefully (UI already updated)',
        build: () {
          when(mockBookOrderService.saveCurrentOrder(any))
              .thenThrow(Exception('Save failed'));
          return cubit;
        },
        seed: () => BookListLoaded([testBook1, testBook2]),
        act: (cubit) => cubit.reorderBooks(0, 2), // ReorderableListView passes 2 to move from 0 to 1
        expect: () => [
          BookListLoaded([testBook2, testBook1]),
        ],
        // Should not emit error - just log it
      );
    });
  });
}
