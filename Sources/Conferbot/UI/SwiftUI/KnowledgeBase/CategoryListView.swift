//
//  CategoryListView.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// View displaying a list of knowledge base categories
@available(iOS 14.0, *)
public struct CategoryListView: View {
    let categories: [KnowledgeBaseCategory]
    let onCategorySelected: (KnowledgeBaseCategory) -> Void

    @State private var animateItems = false

    public init(
        categories: [KnowledgeBaseCategory],
        onCategorySelected: @escaping (KnowledgeBaseCategory) -> Void
    ) {
        self.categories = categories
        self.onCategorySelected = onCategorySelected
    }

    public var body: some View {
        Group {
            if categories.isEmpty {
                emptyStateView
            } else {
                categoriesListView
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                animateItems = true
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Empty state illustration
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
            }

            VStack(spacing: 8) {
                Text("No Articles Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Check back later for helpful articles and guides")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Categories List View

    private var categoriesListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Header
                headerView
                    .padding(.top, 8)

                // Categories
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    CategoryRowView(category: category)
                        .onTapGesture {
                            onCategorySelected(category)
                        }
                        .opacity(animateItems ? 1 : 0)
                        .offset(y: animateItems ? 0 : 20)
                        .animation(
                            .easeOut(duration: 0.3).delay(Double(index) * 0.05),
                            value: animateItems
                        )
                }
            }
            .padding()
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse Help Articles")
                .font(.headline)

            Text("Find answers to your questions by browsing our help categories")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

// MARK: - Category Row View

@available(iOS 14.0, *)
struct CategoryRowView: View {
    let category: KnowledgeBaseCategory

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 16) {
            // Category icon
            CategoryIconView(categoryName: category.name, icon: category.icon)
                .frame(width: 48, height: 48)

            // Category info
            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let description = category.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Article count badge
                Text(articleCountText)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(.top, 2)
            }

            Spacer()

            // Arrow
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var articleCountText: String {
        let count = category.articles?.count ?? category.articleCount
        return count == 1 ? "1 article" : "\(count) articles"
    }
}

// MARK: - Featured Categories Section

@available(iOS 14.0, *)
struct FeaturedCategoriesSection: View {
    let categories: [KnowledgeBaseCategory]
    let onCategorySelected: (KnowledgeBaseCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Featured Topics")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories.prefix(4)) { category in
                        FeaturedCategoryCard(category: category)
                            .onTapGesture {
                                onCategorySelected(category)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Featured Category Card

@available(iOS 14.0, *)
struct FeaturedCategoryCard: View {
    let category: KnowledgeBaseCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon
            CategoryIconView(categoryName: category.name, icon: category.icon)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text("\(category.articles?.count ?? category.articleCount) articles")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 140)
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Categories Grid View

@available(iOS 14.0, *)
struct CategoriesGridView: View {
    let categories: [KnowledgeBaseCategory]
    let onCategorySelected: (KnowledgeBaseCategory) -> Void

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(categories) { category in
                CategoryGridItem(category: category)
                    .onTapGesture {
                        onCategorySelected(category)
                    }
            }
        }
    }
}

// MARK: - Category Grid Item

@available(iOS 14.0, *)
struct CategoryGridItem: View {
    let category: KnowledgeBaseCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryIconView(categoryName: category.name, icon: category.icon)
                    .frame(width: 36, height: 36)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(category.articles?.count ?? category.articleCount) articles")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - All Categories Header

@available(iOS 14.0, *)
struct AllCategoriesHeader: View {
    let totalArticles: Int
    let totalCategories: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("All Categories")
                    .font(.headline)

                Text("\(totalArticles) articles in \(totalCategories) categories")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

@available(iOS 14.0, *)
struct CategoryListView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryListView(
            categories: [
                KnowledgeBaseCategory(
                    id: "1",
                    name: "Getting Started",
                    description: "Learn the basics of using our platform",
                    articleCount: 5
                ),
                KnowledgeBaseCategory(
                    id: "2",
                    name: "Account & Settings",
                    description: "Manage your account and preferences",
                    articleCount: 8
                ),
                KnowledgeBaseCategory(
                    id: "3",
                    name: "Billing & Payments",
                    description: "Information about pricing and invoices",
                    articleCount: 4
                ),
                KnowledgeBaseCategory(
                    id: "4",
                    name: "Integrations",
                    description: "Connect with your favorite tools",
                    articleCount: 12
                ),
                KnowledgeBaseCategory(
                    id: "5",
                    name: "Troubleshooting",
                    description: "Solutions to common issues",
                    articleCount: 15
                )
            ],
            onCategorySelected: { _ in }
        )
    }
}
