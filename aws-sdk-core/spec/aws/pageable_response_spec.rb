require 'spec_helper'

module Aws
  describe PageableResponse do

    let(:pager) { Paging::Pager.new(rules) }

    let(:resp) {
      r = Seahorse::Client::Response.new
      r.context[:original_params] = r.context.params
      PageableResponse.new(r, pager)
    }

    # If an operation has no paging metadata, then it is considered
    # un-pageable and will always treat a response as the last page.
    describe 'unpageable-operation' do

      let(:pager) { Paging::NullPager.new }

      it 'returns true from #last_page?' do
        expect(resp.last_page?).to be(true)
        expect(resp.next_page?).to be(false)
      end

      it 'raises a LastPageError when calling next_page' do
        expect { resp.next_page }.to raise_error(PageableResponse::LastPageError)
      end

      it 'popualtes the error with the response' do
        begin
          resp.next_page
        rescue => error
          expect(error.response).to be(resp)
        end
      end

    end

    describe 'pagable operations' do

      let(:rules) {{
        'input_token' => 'Offset',
        'output_token' => 'NextToken',
      }}

      it 'returns false from last page if the paging token value is present' do
        resp.data = { 'next_token' => 'OFFSET' }
        expect(resp.last_page?).to be(false)
        expect(resp.next_page?).to be(true)
      end

      it 'is not pageable if response data does not contain tokens' do
        resp.data = { }
        expect(resp.last_page?).to be(true)
        expect(resp.next_page?).to be(false)
      end

      it 'is not pageable if next token is an empty hash' do
        resp.data = { 'next_token' => {} }
        expect(resp.last_page?).to be(true)
        expect(resp.next_page?).to be(false)
      end

      it 'is not pageable if next token is an empty array' do
        resp.data = { 'next_token' => [] }
        expect(resp.last_page?).to be(true)
        expect(resp.next_page?).to be(false)
      end

      it 'responds to #next_page by sending a new request with tokens applied' do
        client = double('client')
        new_request = double('new-request')

        resp.data = { 'next_token' => 'OFFSET' }
        resp.context.client = client
        resp.context.operation_name = 'operation-name'

        expect(client).to receive(:build_request).
          with('operation-name', { :offset => 'OFFSET' }).
          and_return(new_request)

        expect(new_request).to receive(:send_request).
          and_return(Seahorse::Client::Response.new)

        resp.next_page
      end

    end

    describe 'paging with multiple tokens' do

      let(:rules) {{
        'input_token' => ['OffsetA', 'OffsetB'],
        'output_token' => ['Group', 'Value'],
      }}

      it 'returns false from last page if all paging tokens are present' do
        resp.data = { 'group' => 'a', 'value' => 'b' }
        expect(resp.last_page?).to be(false)
        expect(resp.next_page?).to be(true)
      end

      it 'returns false from last page if ANY paging token is present' do
        resp.data = { 'group' => 'a' }
        expect(resp.last_page?).to be(false)
        expect(resp.next_page?).to be(true)
      end

      it 'returns true from last page if NO paging tokens are present' do
        resp.data = { }
        expect(resp.last_page?).to be(true)
        expect(resp.next_page?).to be(false)
      end

      it 'sends any tokens found a request params' do
        client = double('client')
        new_request = double('new-request', send_request: nil)

        resp.data = { 'group' => 'a' }
        resp.context.client = client
        resp.context.operation_name = 'operation-name'

        expect(client).to receive(:build_request).
          with('operation-name', { :offset_a => 'a' }).
          and_return(new_request)

        allow(new_request).to receive(:send_request).and_return(resp)

        resp.next_page
      end

    end

    describe 'paging with truncation indicator' do

      let(:rules) {{
        'input_token' => 'Marker',
        'output_token' => 'NextMarker',
        'more_results' => 'IsTruncated',
      }}

      it 'returns false from last page if the truncation marker is true' do
        resp.data = { 'is_truncated' => true }
        expect(resp.last_page?).to be(false)
        expect(resp.next_page?).to be(true)
      end

      it 'returns true from last page if the truncation marker is false' do
        resp.data = { 'is_truncated' => false }
        expect(resp.last_page?).to be(true)
        expect(resp.next_page?).to be(false)
      end

    end

    describe '#each_page' do

      let(:rules) {{
        'input_token' => 'Offset',
        'output_token' => 'NextToken',
      }}

      it 'yields once per paging result' do
        client = double('client')
        new_request = double('new-request')

        resp.data = { 'next_token' => 'OFFSET' }
        resp.context.client = client
        resp.context.operation_name = 'operation-name'

        resp2 = Seahorse::Client::Response.new
        resp2.data = {}

        allow(client).to receive(:build_request).
          with('operation-name', { :offset => 'OFFSET' }).
          and_return(new_request)

        allow(new_request).to receive(:send_request).and_return(resp2)

        pages = []
        resp.each { |r| pages << r.data }
        expect(pages).to eq([resp.data, resp2.data])
      end

    end

    describe '#count' do

      it 'raises not implemented error by default' do
        data = double('data')
        resp = double('resp', data:data, error:nil, context:nil)
        page = PageableResponse.new(resp, Paging::NullPager.new)
        expect {
          page.count
        }.to raise_error(NotImplementedError)
      end

      it 'passes count from the raises not implemented error by default' do
        data = double('data', count: 10)
        resp = double('resp', data:data, error:nil, context:nil)
        page = PageableResponse.new(resp, Paging::NullPager.new)
        expect(page.count).to eq(10)
      end

      it 'returns false from respond_to when count not present' do
        data = double('data')
        resp = double('resp', data:data, error:nil, context:nil)
        page = PageableResponse.new(resp, Paging::NullPager.new)
        expect(page.respond_to?(:count)).to be(false)
      end

      it 'indicates it responds to count when data#count exists' do
        data = double('data', count: 10)
        resp = double('resp', data:data, error:nil, context:nil)
        page = PageableResponse.new(resp, Paging::NullPager.new)
        expect(page.respond_to?(:count))
      end

    end
  end
end
